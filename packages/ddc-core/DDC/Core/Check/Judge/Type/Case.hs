
module DDC.Core.Check.Judge.Type.Case
        (checkCase)
where
import DDC.Core.Check.Judge.Type.Base
import qualified DDC.Type.Sum   as Sum
import qualified Data.Map       as Map
import Data.List                as L

---------------------------------------------------------------------------------------------------
checkCase :: Checker a n
checkCase !table !ctx0 xx@(XCase a xDiscrim alts) mode
 = do   let config      = tableConfig table

        -- There must be at least one alternative, even if there are no data
        -- constructors. The rest of the checking code assumes this, and will
        -- throw an unhelpful error if there are no alternatives.
        when (null alts)
         $ throw $ ErrorCaseNoAlternatives a xx

        -- Decide what mode to use when checking the discriminant.
        (modeDiscrim, ctx1)
         <- takeDiscrimCheckModeFromAlts table a ctx0 mode alts

        -- Check the discriminant.
        (xDiscrim', tDiscrim, effsDiscrim, ctx2)
         <- tableCheckExp table table ctx1 xDiscrim modeDiscrim

        -- Split the type into the type constructor names and type parameters.
        -- Also check that it's algebraic data, and not a function or effect
        -- type etc.
        (mDataMode, tsArgs)
         <- case takeTyConApps tDiscrim of
             Just (tc, ts)
              -- The unit data type.
              | TyConSpec TcConUnit         <- tc
              -> return ( Just (DataModeSmall [])
                        , [] )

              -- User defined or imported data types.
              | TyConBound (UName nTyCon) _ <- tc
              , Just dataType  <- Map.lookup nTyCon
                               $  dataDefsTypes $ configDataDefs config
              , k              <- kindOfDataType dataType
              , takeResultKind k == kData
              -> return ( lookupModeOfDataType nTyCon (configDataDefs config)
                        , ts )

              -- Primitive data types.
              | TyConBound (UPrim nTyCon _) k <- tc
              , takeResultKind k == kData
              -> return ( lookupModeOfDataType nTyCon (configDataDefs config)
                        , ts )

             _ -> throw $ ErrorCaseScrutineeNotAlgebraic a xx tDiscrim

        -- Get the mode of the data type,
        --   this tells us how many constructors there are.
        dataMode
         <- case mDataMode of
             Nothing -> throw $ ErrorCaseScrutineeTypeUndeclared a xx tDiscrim
             Just m  -> return m

        -- If we're doing bidirectional checking then we don't infer a separate
        -- type for each alternative. Instead, pass down the same existential.
        (modeAlts, ctx3)
         <- case mode of
                Recon   -> return (mode, ctx2)
                Check{} -> return (mode, ctx2)
                Synth
                 -> do  iA       <- newExists kData
                        let tA   = typeOfExists iA
                        let ctx3 = pushExists iA ctx2
                        return (Check tA, ctx3)

        -- Check the alternatives.
        (alts', tsAlts, effss, ctx4)
         <- checkAltsM table a xx tDiscrim tsArgs modeAlts alts ctx3

        -- Check that all the alternatives have the same type.
        --   In Synth mode this is enforced by passing down an existential to
        --   unifify against, but with Recon and Check modes we might get
        --   a different type for each alternative.
        let tsAlts'     = map (applyContext ctx4) tsAlts
        let tAlt : _    = tsAlts'
        forM_ tsAlts' $ \tAlt'
         -> when (not $ equivT tAlt tAlt')
          $ throw $ ErrorCaseAltResultMismatch a xx tAlt tAlt'

        -- Check for overlapping alternatives.
        checkAltsOverlapping a xx alts

        -- Check that alternatives are exhaustive.
        checkAltsExhaustive a xx dataMode alts

        let effsMatch
                = Sum.singleton kEffect
                $ crushEffect $ tHeadRead tDiscrim

        ctrace  $ vcat
                [ text "* Case"
                , text "  modeDiscrim"  <+> ppr modeDiscrim
                , text "  tAlt = "      <+> ppr tAlt
                , indent 2 $ ppr ctx0
                , indent 2 $ ppr ctx1
                , indent 2 $ ppr ctx2
                , indent 2 $ ppr ctx4
                , empty ]

        returnX a
                (\z -> XCase z xDiscrim' alts')
                tAlt
                (Sum.unions kEffect (effsDiscrim : effsMatch : effss))
                ctx4

checkCase _ _ _ _
        = error "ddc-core.checkCase: no match"


---------------------------------------------------------------------------------------------------
-- | Decide what type checker mode to use when checking the discriminant
--   of a case expression.
--
--   With plain type reconstruction then we also reconsruct the discrim type.
--
--   With bidirectional checking we use the type of the patterns as
--   the expected type when checking the discriminant.
--
takeDiscrimCheckModeFromAlts
        :: Ord n
        => Table a n          -- ^ Checker table.
        -> a                  -- ^ Annotation for error messages.
        -> Context n          -- ^ Current context.
        -> Mode n             -- ^ Mode for checking enclosing case expression.
        -> [Alt a n]          -- ^ Alternatives in the case expression.
        -> CheckM a n
                ( Mode n
                , Context n)

takeDiscrimCheckModeFromAlts table a ctx mode alts
 | Recon        <- mode
 = return (Recon, ctx)

 | otherwise
 = do   -- Get the result type associated with each of the patterns.
        -- NOTE: We don't bother checking the result types match here.
        --       This will be done by checkAltsM when we check each individual
        --       pattern type against the type of the scrutinee.
        let pats     = map patOfAlt alts
        tsPats       <- liftM catMaybes $ mapM (dataTypeOfPat table a) pats

        case tsPats of
         -- We only have a default pattern,
         -- so will need to synthesise the type of the discrim without
         -- an expected type.
         []
          -> return (Synth, ctx)

         -- We have at least one non-default pattern, which we can use to
         -- determine how many existentials are needed to instantiate
         -- the quantifiers of its type.
         tPat : _
          | Just (bs, tBody) <- takeTForalls tPat
          -> do
                -- existentials for all of the type parameters.
                is        <- mapM  (\_ -> newExists kData) bs
                let ts     = map typeOfExists is
                let ctx'   = foldl (flip pushExists) ctx is
                let tBody' = substituteTs (zip bs ts) tBody
                return (Check tBody', ctx')

          | otherwise
          -> return (Check tPat, ctx)


---------------------------------------------------------------------------------------------------
-- | Check some case alternatives.
checkAltsM
        :: (Show a, Show n, Pretty n, Ord n)
        => Table a n            -- ^ Checker table.
        -> a                    -- ^ Annotation for error messages.
        -> Exp a n              -- ^ Whole case expression, for error messages.
        -> Type n               -- ^ Type of discriminant.
        -> [Type n]             -- ^ Args to type constructor of discriminant.
        -> Mode n               -- ^ Check mode for the alternatives.
        -> [Alt a n]            -- ^ Alternatives to check.
        -> Context n            -- ^ Context to check the alternatives in.
        -> CheckM a n
                ( [Alt (AnTEC a n) n]      -- Checked alternatives.
                , [Type n]                 -- Type of alternative results.
                , [TypeSum n]              -- Alternative effects.
                , Context n)

checkAltsM !table !a !xx !tDiscrim !tsArgs !mode !alts0 !ctx
 = checkAltsM1 alts0 ctx

 where
  -- Whether we're doing bidirectional type inference.
  bidir
   = case mode of
        Recon   -> False
        _       -> True

  -- Check all the alternatives monadically.
  checkAltsM1 [] ctx0
   =    return ([], [], [], ctx0)

  checkAltsM1 (alt : alts) ctx0
   = do (alt',  tAlt,  eAlt, ctx1)
         <- checkAltM   alt ctx0

        (alts', tsAlts, esAlts, ctx2)
         <- checkAltsM1 alts ctx1

        return  ( alt'  : alts'
                , tAlt  : tsAlts
                , eAlt  : esAlts
                , ctx2)

  -- Check a single alternative.
  checkAltM   (AAlt PDefault xBody) !ctx0
   = do
        -- Check the right of the alternative.
        (xBody', tBody, effBody, ctx1)
                <- tableCheckExp table table ctx0 xBody mode

        return  ( AAlt PDefault xBody'
                , tBody
                , effBody
                , ctx1)

  checkAltM alt@(AAlt (PData dc bsArg) xBody) !ctx0
   = do
        -- Get the constructor type associated with this pattern.
        Just tCtor <- ctorTypeOfPat table a (PData dc bsArg)

        -- Take the type of the constructor and instantiate it with the
        -- type arguments we got from the discriminant. If the ctor type
        -- doesn't instantiate then it won't have enough foralls on the front,
        -- which should have been checked by the def checker.
        tCtor_inst
         <- if equivT tCtor tDiscrim
             then return tCtor
             else case instantiateTs tCtor tsArgs of
                   Nothing -> throw $ ErrorCaseCannotInstantiate a xx tDiscrim tCtor
                   Just t  -> return t

        -- Split the constructor type into the field and result types.
        let (tsFields_ctor, tResult)
                = takeTFunArgResult tCtor_inst

        -- The result type of the constructor must match the discriminant type.
        -- If it doesn't then the constructor in the pattern probably isn't for
        -- the discriminant type.
        when (not $ equivT tDiscrim tResult)
         $ throw $ ErrorCaseScrutineeTypeMismatch a xx
                        tDiscrim tResult

        -- There must be at least as many fields as variables in the pattern.
        -- It's ok to bind less fields than provided by the constructor.
        when (length tsFields_ctor < length bsArg)
         $ throw $ ErrorCaseTooManyBinders a xx dc
                        (length tsFields_ctor) (length bsArg)

        -- Merge the field types we get by instantiating the constructor
        -- type with possible annotations from the source program.
        -- If the annotations don't match, then we throw an error.
        (tsFields, ctx1)
                <- checkFieldAnnots table bidir a xx
                        (zip tsFields_ctor (map typeOfBind bsArg))
                        ctx0

        -- Extend the environment with the field types.
        let bsArg'         = zipWith replaceTypeOfBind tsFields bsArg
        let (ctx2, posArg) = markContext ctx1
        let ctxArg         = pushTypes bsArg' ctx2

        -- Check the body in this new environment.
        (xBody', tBody, effsBody, ctxBody)
                 <- tableCheckExp table table ctxArg xBody mode

        let tBody'      = applyContext ctxBody tBody

        -- Pop the argument types from the context.
        let ctx_cut     = popToPos posArg ctxBody

        ctrace  $ vcat
                [ text "* Alt"
                , ppr alt
                , text "  MODE:   " <+> ppr mode
                , text "  tBody': " <+> ppr tBody'
                , ppr ctx0
                , ppr ctxBody
                , ppr ctx_cut
                , empty ]

        -- We're returning the new context for kicks,
        -- but the caller doesn't use it because we don't want the order of
        -- alternatives to matter for type inference.
        return  ( AAlt (PData dc bsArg') xBody'
                , tBody'
                , effsBody
                , ctx_cut)


-- Fields -----------------------------------------------------------------------------------------
-- | Check the inferred type for a field against any annotation for it.
checkFieldAnnots
        :: (Show a, Show n, Ord n, Pretty n)
        => Table a n            -- ^ Checker table.
        -> Bool                 -- ^ Use bi directional type inference.
        -> a                    -- ^ Annotation for error messages.
        -> Exp a n              -- ^ Whole case expression for error messages.
        -> [(Type n, Type n)]   -- ^ List of inferred and annotation types.
        -> Context n
        -> CheckM a n
                ( [Type n]      --   Final types for each field.
                , Context n)    --   Result context.

checkFieldAnnots table bidir a xx tts ctx0
 = case tts of
        [] -> return ([], ctx0)
        (tActual, tAnnot) : tts'
           -> do (tField,   ctx1)  <- checkFieldAnnot tActual tAnnot ctx0
                 (tsFields, ctx')  <- checkFieldAnnots table bidir a xx tts' ctx1
                 return (tField : tsFields, ctx')

 where checkFieldAnnot tActual tAnnot ctx
        -- Annotation is bottom, so use the inferred type of the field.
        | isBot tAnnot
        = return (tActual, ctx)

        -- With bidirectional checking, annotations on fields can refine the
        -- inferred type for the overal expression.
        | bidir
        = do    ctx'    <- makeEq (tableConfig table) a ctx tAnnot tActual
                        $  ErrorCaseFieldTypeMismatch a xx tAnnot tActual

                let tField = applyContext ctx' tActual
                return  (tField, ctx')

        -- In Recon mode, if there is an annotation on the field then it needs
        -- to exactly match the inferred type of the field.
        | not bidir
        , equivT tActual tAnnot
        = return (tAnnot, ctx)

        -- Annotation does not match actual type.
        | otherwise
        = throw $ ErrorCaseFieldTypeMismatch a xx tAnnot tActual


-- Ctor Types -------------------------------------------------------------------------------------
-- | Get the constructor type associated with a pattern, or Nothing for the
--   default pattern. If the data constructor isn't defined then the spread
--   transform won't have given it a proper type.
--   Note that we can't simply check whether the constructor is in the
---  environment because literals like 42# never are.
ctorTypeOfPat
        :: Ord n
        => Table a n            -- ^ Checker table.
        -> a                    -- ^ Annotation for error messages.
        -> Pat n                -- ^ Pattern.
        -> CheckM a n (Maybe (Type n))

ctorTypeOfPat table a (PData dc _)
 = case dc of
        DaConUnit   -> return $ Just $ tUnit
        DaConPrim{} -> return $ Just $ daConType dc

        DaConBound n
         -- Types of algebraic data ctors should be in the defs table.
         |  Just ctor <- Map.lookup n
                                $ dataDefsCtors
                                $ configDataDefs $ tableConfig table
         -> return $ Just $ typeOfDataCtor ctor

         | otherwise
         -> throw  $ ErrorUndefinedCtor a $ XCon a dc

ctorTypeOfPat _table _a PDefault
 = return Nothing


-- | Get the data type associated with a pattern,
--   or Nothing for the default pattern.
--
--   Yields  the data type with outer quantifiers for its type parametrs.
--   For example, given pattern (Cons x xs), return (forall [a : Data]. List a)
--
dataTypeOfPat
        :: Ord n
        => Table a n            -- ^ Checker table.
        -> a                    -- ^ Annotation for error messages.
        -> Pat n                -- ^ Pattern.
        -> CheckM a n (Maybe (Type n))

dataTypeOfPat table a pat
 = do   mtCtor      <- ctorTypeOfPat table a pat

        case mtCtor of
         Nothing    -> return Nothing
         Just tCtor -> return $ Just $ eat [] tCtor

 where  eat bs tt
         = case tt of
                TForall b t        -> eat (bs ++ [b]) t
                TApp{}
                 |  Just (_t1, t2) <- takeTFun tt
                 -> eat bs t2
                _                  -> foldr TForall tt bs


---------------------------------------------------------------------------------------------------
-- | Check for overlapping alternatives,
--   and throw an error in the `CheckM` monad if there are any.
checkAltsOverlapping
        :: Eq n
        => a                    -- ^ Annotation for error messages.
        -> Exp a n              -- ^ Expression for error messages.
        -> [Alt a n]            -- ^ Alternatives to check.
        -> CheckM a n ()

checkAltsOverlapping a xx alts
 = do   let pats                = [p | AAlt p _ <- alts]
        let psDefaults          = filter isPDefault pats
        let nsCtorsMatched      = mapMaybe takeCtorNameOfAlt alts

        -- Alts were overlapping because there are multiple defaults.
        when (length psDefaults > 1)
         $ throw $ ErrorCaseOverlapping a xx

        -- Alts were overlapping because the same ctor is used multiple times.
        when (length (nub nsCtorsMatched) /= length nsCtorsMatched )
         $ throw $ ErrorCaseOverlapping a xx

        -- Check for alts overlapping because a default is not last.
        -- Also check there is at least one alternative.
        case pats of
          [] -> throw $ ErrorCaseNoAlternatives a xx

          _  |  Just patsInit <- takeInit pats
             ,  or $ map isPDefault $ patsInit
             -> throw $ ErrorCaseOverlapping a xx

             |  otherwise
             -> return ()


---------------------------------------------------------------------------------------------------
-- | Check that the alternatives are exhaustive,
--   and throw and error in the `CheckM` monad if they're not.
checkAltsExhaustive
        :: Eq n
        => a                -- ^ Annotation for error messages.
        -> Exp a n          -- ^ Expression for error messages.
        -> DataMode n       -- ^ Mode of data type.
                            --   Tells us how many data constructors to expect.
        -> [Alt a n]        -- ^ Alternatives to check.
        -> CheckM a n ()

checkAltsExhaustive a xx mode alts
 = do   let nsCtorsMatched      = mapMaybe takeCtorNameOfAlt alts

        -- Check that alternatives are exhaustive.
        case mode of

          -- Small types have some finite number of constructors.
          DataModeSmall nsCtors
           -- If there is a default alternative then we've covered all the
           -- possibiliies. We know this we've also checked for overlap.
           | any isPDefault [p | AAlt p _ <- alts]
           -> return ()

           -- Look for unmatched constructors.
           | nsCtorsMissing <- nsCtors \\ nsCtorsMatched
           , not $ null nsCtorsMissing
           -> throw $ ErrorCaseNonExhaustive a xx nsCtorsMissing

           -- All constructors were matched.
           | otherwise
           -> return ()

          -- Large types have an effectively infinite number of constructors
          -- (like integer literals), so there needs to be a default alt.
          DataModeLarge
           | any isPDefault [p | AAlt p _ <- alts] -> return ()
           | otherwise
           -> throw $ ErrorCaseNonExhaustiveLarge a xx

