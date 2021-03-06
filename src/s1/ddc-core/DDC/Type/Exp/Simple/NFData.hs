
module DDC.Type.Exp.Simple.NFData where
import DDC.Type.Exp.Simple.Exp
import Control.DeepSeq


instance NFData n => NFData (Binder n) where
 rnf bb
  = case bb of
        RNone   -> ()
        RAnon   -> ()
        RName n -> rnf n


instance NFData n => NFData (Bind n) where
 rnf bb
  = case bb of
        BNone t         -> rnf t
        BAnon t         -> rnf t
        BName n t       -> rnf n `seq` rnf t


instance NFData n => NFData (Bound n) where
 rnf uu
  = case uu of
        UIx   i         -> rnf i
        UName n         -> rnf n


instance NFData n => NFData (Type n) where
 rnf tt
  = case tt of
        TVar u          -> rnf u
        TCon tc         -> rnf tc
        TAbs    b t     -> rnf b  `seq` rnf t
        TApp    t1 t2   -> rnf t1 `seq` rnf t2
        TForall b t     -> rnf b  `seq` rnf t
        TSum    ts      -> rnf ts
        TRow    row     -> rnf row


instance NFData n => NFData (TypeSum n) where
 rnf !ts
  = case ts of
        TypeSumBot{}
         -> rnf (typeSumKind ts)

        TypeSumSet{}
         ->    rnf (typeSumKind       ts)
         `seq` rnf (typeSumElems      ts)
         `seq` rnf (typeSumBoundNamed ts)
         `seq` rnf (typeSumBoundAnon  ts)
         `seq` rnf (typeSumSpill      ts)


instance NFData TyConHash where
 rnf (TyConHash i)
  = rnf i


instance NFData n => NFData (TypeSumVarCon n) where
 rnf ts
  = case ts of
        TypeSumVar u            -> rnf u
        TypeSumCon n            -> rnf n


instance NFData n => NFData (TyCon n) where
 rnf tc
  = case tc of
        TyConSort    _          -> ()
        TyConKind    _          -> ()
        TyConWitness _          -> ()
        TyConSpec    _          -> ()
        TyConBound   con        -> rnf con
        TyConExists  n   k      -> rnf n   `seq` rnf k

