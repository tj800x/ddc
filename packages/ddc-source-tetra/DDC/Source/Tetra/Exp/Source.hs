{-# LANGUAGE TypeFamilies #-}
module DDC.Source.Tetra.Exp.Source
        ( -- * Language
          Source        (..)

          -- * Binding
        , Bind          (..)
        , Bound         (..)

          -- * Types
          -- ** Syntax
        , GTAnnot
        , GTBindVar,    GTBoundVar
        , GTBindCon,    GTBoundCon
        , GTPrim

        , Type,         GType  (..)
        , TyCon,        GTyCon (..)

        , SoCon         (..)
        , KiCon         (..)
        , TwCon         (..)
        , TcCon         (..)

        , TyConBind     (..)
        , TyConBound    (..)

        , pattern TApp2, pattern TApp3
        , pattern TApp4, pattern TApp5

        , pattern TVoid, pattern TUnit
        , pattern TFun
        , pattern TBot,  pattern TSum
        , pattern TPrim

          -- ** Primitives 
        , PrimType       (..)
        , PrimTyCon      (..)
        , PrimTyConTetra (..)

        , pattern KData, pattern KRegion, pattern KEffect
        , pattern TImpl
        , pattern TSusp
        , pattern TRead, pattern TWrite,  pattern TAlloc

        , pattern TBool
        , pattern TNat,  pattern TInt
        , pattern TSize, pattern TWord
        , pattern TFloat
        , pattern TTextLit

          -- * Terms
          -- ** Syntax
        , GXAnnot
        , GXBindVar,    GXBoundVar
        , GXBindCon,    GXBoundCon
        , GXPrim

        , BindVarMT,    GXBindVarMT (..)
        , Exp,          GExp        (..)
        , Lets,         GLets       (..)
        , Clause,       GClause     (..)
        , AltMatch,     GAltMatch   (..)
        , AltCase,      GAltCase    (..)
        , Pat,          GPat        (..)
        , GuardedExp,   GGuardedExp (..)
        , Guard,        GGuard      (..)
        , Cast,         GCast       (..)
        , Witness,      GWitness    (..)
        , WiCon,        GWiCon      (..)
        , DaCon (..)

        , DaConBind     (..)
        , DaConBound    (..)

          -- ** Primitives
        , PrimVal       (..)
        , PrimArith     (..)
        , OpVector      (..)
        , OpFun         (..)
        , OpError       (..)
        , PrimLit       (..)

        , pattern PTrue
        , pattern PFalse

          -- ** Dictionaries
        , ShowLanguage)
where
import DDC.Source.Tetra.Exp.Generic
import DDC.Source.Tetra.Exp.Bind
import DDC.Source.Tetra.Prim
import DDC.Type.Exp.TyCon               as T
import DDC.Data.SourcePos
import DDC.Base.Pretty


-- Language -------------------------------------------------------------------
-- | Type index for Source Tetra Language.
data Source     
        = Source
        deriving Show

instance Pretty Source where
 ppr ss = text (show ss)


instance HasAnonBind Source where
 isAnon _ BAnon = True
 isAnon _ _     = False


instance Anon Source where
 withBindings Source n f
  = let bs      = replicate n BAnon
        us      = reverse [UIx i | i <- [0..(n - 1)]]
    in  f bs us


-- Type AST -------------------------------------------------------------------
type Type       = GType  Source
type TyCon      = GTyCon Source

type instance GTAnnot    Source = SourcePos
type instance GTBindVar  Source = Bind
type instance GTBoundVar Source = Bound
type instance GTBindCon  Source = TyConBind
type instance GTBoundCon Source = TyConBound
type instance GTPrim     Source = PrimType


-- Term AST -------------------------------------------------------------------
type BindVarMT  = GXBindVarMT Source
type Exp        = GExp        Source
type Lets       = GLets       Source
type Clause     = GClause     Source
type AltCase    = GAltCase    Source
type AltMatch   = GAltMatch   Source
type Pat        = GPat        Source
type GuardedExp = GGuardedExp Source
type Guard      = GGuard      Source
type Cast       = GCast       Source
type Witness    = GWitness    Source
type WiCon      = GWiCon      Source

type instance GXAnnot    Source = SourcePos
type instance GXBindVar  Source = Bind
type instance GXBoundVar Source = Bound
type instance GXBindCon  Source = DaConBind
type instance GXBoundCon Source = DaConBound
type instance GXPrim     Source = PrimVal


