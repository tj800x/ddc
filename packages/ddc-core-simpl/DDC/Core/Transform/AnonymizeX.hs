
module DDC.Core.Transform.AnonymizeX
        ( anonymizeX
        , AnonymizeX(..))
where
import DDC.Core.Module
import DDC.Core.Exp
import DDC.Type.Transform.AnonymizeT
import DDC.Type.Compounds
import Control.Monad
import Data.List


-- | Rewrite all binders in a thing to be of anonymous form.
anonymizeX :: (Ord n, AnonymizeX c) => c n -> c n
anonymizeX xx
        = anonymizeWithX [] [] xx


-------------------------------------------------------------------------------
class AnonymizeX (c :: * -> *) where

 -- | Rewrite all binders in a thing to be anonymous.
 --   The stacks contains existing anonymous binders that we have entered into,
 --   and named binders that we have rewritten. All bound occurrences of variables
 --   will be replaced by references into these stacks.
 anonymizeWithX 
        :: forall n. Ord n 
        => [Bind n]     -- ^ Stack for Spec binders (level-1).
        -> [Bind n]     -- ^ Stack for Data and Witness binders (level-0).
        -> c n -> c n

instance AnonymizeX (Module a) where
 anonymizeWithX kstack tstack mm@ModuleCore{}
  = let x'   = anonymizeWithX kstack tstack (moduleBody mm)
    in  mm { moduleBody = x' }


instance AnonymizeX (Exp a) where
 anonymizeWithX kstack tstack xx
  = let down = anonymizeWithX kstack tstack
    in case xx of
        -- The types on prims and cons are guaranteed to be closed,
        -- so there is no need to erase them.
        XVar _ UPrim{}  -> xx
        XCon{}          -> xx      

        -- Erase types on variables because they might
        -- have free variables.
        XVar a u@(UName{})       
         |  Just ix      <- findIndex (boundMatchesBind u) tstack
         -> XVar a (UIx ix)

        XVar a u
         -> XVar a u

        XApp a x1 x2    -> XApp a (down x1) (down x2)

        XLAM a b x
         -> let (kstack', b')   = pushAnonymizeBindT kstack b
            in  XLAM a b'   (anonymizeWithX kstack' tstack x)

        XLam a b x
         -> let (tstack', b')   = pushAnonymizeBindX kstack tstack b
            in  XLam a b'   (anonymizeWithX kstack tstack' x)

        XLet a lts x
         -> let (kstack', tstack', lts')  
                 = pushAnonymizeLets kstack tstack lts
            in  XLet a lts' (anonymizeWithX kstack' tstack' x)

        XCase a x alts  -> XCase a  (down x) (map down alts)
        XCast a c x     -> XCast a  (down c) (down x)
        XType t         -> XType    (anonymizeWithT kstack t)
        XWitness w      -> XWitness (down w)


instance AnonymizeX (Cast a) where
 anonymizeWithX kstack tstack cc
  = case cc of
        CastWeakenEffect eff
         -> CastWeakenEffect  (anonymizeWithT kstack eff)

        CastWeakenClosure xs
         -> CastWeakenClosure (map (anonymizeWithX kstack tstack) xs)

        CastPurify w
         -> CastPurify        (anonymizeWithX kstack tstack w)

        CastForget w
         -> CastForget        (anonymizeWithX kstack tstack w)


instance AnonymizeX LetMode where
 anonymizeWithX kstack tstack lm
  = case lm of
        LetStrict       -> lm
        LetLazy mw      -> LetLazy $ liftM (anonymizeWithX kstack tstack) mw


instance AnonymizeX (Alt a) where
 anonymizeWithX kstack tstack alt
  = case alt of
        AAlt PDefault x
         -> AAlt PDefault (anonymizeWithX kstack tstack x)

        AAlt (PData uCon bs) x
         -> let (tstack', bs')  = pushAnonymizeBindXs kstack tstack bs
                x'              = anonymizeWithX kstack tstack' x
            in  AAlt (PData uCon bs') x'


instance AnonymizeX Witness where
 anonymizeWithX kstack tstack ww
  = let down = anonymizeWithX kstack tstack 
    in case ww of
        WVar u@(UName _)
         |  Just ix      <- findIndex (boundMatchesBind u) tstack
         -> WVar (UIx ix)

        WVar u          -> WVar u
        WCon  c         -> WCon  c
        WApp  w1 w2     -> WApp  (down w1) (down w2)
        WJoin w1 w2     -> WJoin (down w1) (down w2)
        WType t         -> WType (anonymizeWithT kstack t)


instance AnonymizeX Bind where
 anonymizeWithX kstack _tstack bb
  = let t'      = anonymizeWithT kstack $ typeOfBind bb
    in  replaceTypeOfBind t' bb 

-- Push ----------------------------------------------------------------------
-- Push a binding occurrence of a type variable on the stack, 
--  returning the anonyized binding occurrence and the new stack.
pushAnonymizeBindX 
        :: Ord n 
        => [Bind n]     -- ^ Stack for Spec binders (kind environment)
        -> [Bind n]     -- ^ Stack for Value and Witness binders (type environment)
        -> Bind n 
        -> ([Bind n], Bind n)

pushAnonymizeBindX kstack tstack b@BNone{}
 = let  b'      = anonymizeWithX kstack tstack b
        t'      = typeOfBind b'
   in   (tstack,  BNone t')

pushAnonymizeBindX kstack tstack b
 = let  b'      = anonymizeWithX kstack tstack b
        t'      = typeOfBind b'
        tstack' = b' : tstack
   in   (tstack', BAnon t')


-- Push a binding occurrence on the stack, 
--  returning the anonyized binding occurrence and the new stack.
-- Used in the definition of `anonymize`.
pushAnonymizeBindXs 
        :: Ord n 
        => [Bind n]     -- ^ Stack for Spec binders (kind environment)
        -> [Bind n]     -- ^ Stack for Value and Witness binders (type environment)
        -> [Bind n] 
        -> ([Bind n], [Bind n])

pushAnonymizeBindXs kstack tstack bs
  = mapAccumL   (\tstack' b -> pushAnonymizeBindX kstack tstack' b)
                tstack bs


pushAnonymizeLets 
        :: Ord n 
        => [Bind n] 
        -> [Bind n] 
        -> Lets a n 
        -> ([Bind n], [Bind n], Lets a n)

pushAnonymizeLets kstack tstack lts
 = case lts of
        LLet mode b x
         -> let mode'           = anonymizeWithX     kstack tstack mode
                x'              = anonymizeWithX     kstack tstack x
                (tstack', b')   = pushAnonymizeBindX kstack tstack b
            in  (kstack, tstack', LLet mode' b' x')

        LRec bxs 
         -> let (bs, xs)        = unzip bxs
                (tstack', bs')  = pushAnonymizeBindXs kstack tstack   bs
                xs'             = map (anonymizeWithX kstack tstack') xs
                bxs'            = zip bs' xs'
            in  (kstack, tstack', LRec bxs')

        LLetRegion b bs
         -> let (kstack', b')   = pushAnonymizeBindT  kstack b
                (tstack', bs')  = pushAnonymizeBindXs kstack' tstack bs
            in  (kstack', tstack', LLetRegion b' bs')

        LWithRegion{}
         -> (kstack, tstack, lts)

