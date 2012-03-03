module DDCI.Core.Command.Check
        ( cmdShowKind
        , cmdTypeEquiv
        , cmdShowWType
        , cmdShowType
        , cmdExpRecon
        , ShowTypeMode(..)
        , cmdParseCheckExp)
where
import DDCI.Core.State
import DDCI.Core.IO
import DDC.Core.Eval.Profile
import DDC.Core.Eval.Env
import DDC.Core.Eval.Name
import DDC.Core.Eval.Check
import DDC.Type.Equiv
import DDC.Core.Load
import DDC.Core.Exp
import DDC.Core.Check
import DDC.Core.Pretty
import DDC.Core.Parser
import DDC.Core.Parser.Tokens
import DDC.Core.Transform.SpreadX
import DDC.Type.Transform.SpreadT
import qualified DDC.Type.Parser        as T
import qualified DDC.Type.Check         as T
import qualified DDC.Base.Parser        as BP


-- kind ------------------------------------------------------------------------
-- | Show the kind of a type.
cmdShowKind :: State -> Int -> String -> IO ()
cmdShowKind state lineStart str
 = let  toks    = lexString lineStart str
        eTK     = loadType evalProfile "<interactive>" toks
   in   case eTK of
         Left err       -> putStrLn $ renderIndent $ ppr err
         Right (t, k)   -> outDocLn state $ ppr t <+> text "::" <+> ppr k


-- tequiv ---------------------------------------------------------------------
-- | Check if two types are equivlant.
cmdTypeEquiv :: State -> Int -> String -> IO ()
cmdTypeEquiv _state lineStart ss
 = goParse (lexString lineStart ss)
 where
        goParse toks
         = case BP.runTokenParser describeTok "<interactive>"
                        (do t1 <- T.pTypeAtom
                            t2 <- T.pTypeAtom
                            return (t1, t2))
                        toks
            of Left err -> putStrLn $ renderIndent $ text "parse error " <> ppr err
               Right tt -> goEquiv tt
         
        goEquiv (t1, t2)
         = do   b1 <- checkT t1
                b2 <- checkT t2
                if b1 && b2 
                 then putStrLn $ show $ equivT t1 t2    
                 else return ()

        checkT t
         = case T.checkType primDataDefs primKindEnv (spreadT primKindEnv t) of
                Left err 
                 -> do  putStrLn $ renderIndent $ ppr err
                        return False

                Right{} 
                 ->     return True


-- wtype ----------------------------------------------------------------------
-- | Show the type of a witness.
cmdShowWType :: State -> Int -> String -> IO ()
cmdShowWType state lineStart str
 = let  toks    = lexString lineStart str
        eTK     = loadWitness evalProfile "<interactive>" toks
   in   case eTK of
         Left err       -> putStrLn $ renderIndent $ ppr err
         Right (t, k)   -> outDocLn state $ ppr t <+> text "::" <+> ppr k


-- check / type / effect / closure --------------------------------------------
-- | What components of the checked type to display.
data ShowTypeMode
        = ShowTypeAll
        | ShowTypeValue
        | ShowTypeEffect
        | ShowTypeClosure
        deriving (Eq, Show)


-- | Show the type of an expression.
cmdShowType :: State -> ShowTypeMode -> Int -> String -> IO ()
cmdShowType state mode lineStart ss
 = cmdParseCheckExp state lineStart ss >>= goResult
 where
        goResult Nothing
         = return ()

        goResult (Just (x, t, eff, clo))
         = case mode of
                ShowTypeAll
                 -> do  outDocLn state $ ppr x
                        outDocLn state $ text ":*: " <+> ppr t
                        outDocLn state $ text ":!:" <+> ppr eff
                        outDocLn state $ text ":$:" <+> ppr clo
        
                ShowTypeValue
                 -> outDocLn state $ ppr x <+> text "::" <+> ppr t
        
                ShowTypeEffect
                 -> outDocLn state $ ppr x <+> text ":!" <+> ppr eff

                ShowTypeClosure
                 -> outDocLn state $ ppr x <+> text ":$" <+> ppr clo


-- | Check expression and reconstruct type annotations on binders.
cmdExpRecon :: State -> Int -> String -> IO ()
cmdExpRecon state lineStart ss
 = cmdParseCheckExp state lineStart ss >>= goResult
 where
        goResult Nothing
         = return ()

        goResult (Just (x, _, _, _))
         = outDocLn state $ ppr x


-- | Parse the given core expression, 
--   and return it, along with its type, effect and closure.
--
--   If the expression had a parse error, undefined vars, or type error
--   then print this to the console.
cmdParseCheckExp 
        :: State
        -> Int          -- Starting line number.
        -> String 
        -> IO (Maybe ( Exp () Name
                     , Type Name, Effect Name, Closure Name))

cmdParseCheckExp _state lineStart str
 = goParse (lexString lineStart str)
 where
        -- Lex and parse the string.
        goParse toks                
         = case BP.runTokenParser describeTok "<interactive>" pExp toks of
                Left err 
                 -> do  putStrLn $ renderIndent $ ppr err
                        return Nothing
                
                Right x  -> goCheckType (spreadX primKindEnv primTypeEnv x)

        -- Check the type of the expression.
        goCheckType x
         = case checkExp primDataDefs primKindEnv primTypeEnv x of
                Left err
                 -> do  putStrLn $ renderIndent $ ppr err
                        return  Nothing

                Right (x', t, eff, clo)
                 -> goCheckCaps x' t eff clo

        -- Check the initial capabilities in the expression.
        goCheckCaps x t eff clo
         = case checkCapsX x of
                Just err
                 -> do  putStrLn $ renderIndent $ ppr err
                        return Nothing
                        
                Nothing
                 -> return $ Just (x, t, eff, clo)  
         
