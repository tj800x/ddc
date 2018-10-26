
-- | Core language AST with a separate node to hold annotations.
--
--   This version of the AST is used when generating code where most or all
--   of the annotations would be empty. General purpose transformations should
--   deal with the fully annotated version of the AST instead.
--
module DDC.Core.Flow.Exp.Simple.Exp
        ( module DDC.Type.Exp

          -- * Expressions
        , Exp           (..)
        , Cast          (..)
        , Lets          (..)
        , Alt           (..)
        , Pat           (..)

          -- * Witnesses
        , Witness       (..)

          -- * Data Constructors
        , DaCon         (..)

          -- * Witness Constructors
        , WiCon         (..))
where
import DDC.Core.Exp             (WiCon (..), Prim (..))
import DDC.Core.Exp             (DaCon (..))
import DDC.Type.Exp
import DDC.Type.Sum             ()
import Control.DeepSeq


-- Values ---------------------------------------------------------------------
-- | Well-typed expressions have types of kind `Data`.
data Exp a n
        -- | Annotation.
        = XAnnot a (Exp a n)

        -- | Value variable or fragment specific primitive operation.
        | XVar  !(Bound n)

        -- | Primitive operator of the ambient calculus.
        | XPrim !Prim

        -- | Data constructor or literal.
        | XCon  !(DaCon n (Type n))

        -- | Type abstraction (level-1).
        | XLAM  !(Bind n)   !(Exp a n)

        -- | Value and Witness abstraction (level-0).
        | XLam  !(Bind n)   !(Exp a n)

        -- | Application.
        | XApp  !(Exp a n)  !(Exp a n)

        -- | Possibly recursive bindings.
        | XLet  !(Lets a n) !(Exp a n)

        -- | Case branching.
        | XCase !(Exp a n)  ![Alt a n]

        -- | Type cast.
        | XCast !(Cast a n) !(Exp a n)

        -- | Type can appear as the argument of an application.
        | XType    !(Type n)

        -- | Witness can appear as the argument of an application.
        | XWitness !(Witness a n)

        -- | Async binding.
        | XAsync !(Bind n) !(Exp a n) !(Exp a n)
        deriving (Show, Eq)


-- | Possibly recursive bindings.
data Lets a n
        -- | Non-recursive expression binding.
        = LLet     !(Bind n) !(Exp a n)

        -- | Recursive binding of lambda abstractions.
        | LRec     ![(Bind n, Exp a n)]

        -- | Bind a local region variable,
        --   and witnesses to its properties.
        | LPrivate ![Bind n] !(Maybe (Type n)) ![Bind n]
        deriving (Show, Eq)


-- | Case alternatives.
data Alt a n
        = AAlt !(Pat n) !(Exp a n)
        deriving (Show, Eq)


-- | Pattern matching.
data Pat n
        -- | The default pattern always succeeds.
        = PDefault

        -- | Match a data constructor and bind its arguments.
        | PData !(DaCon n (Type n)) ![Bind n]
        deriving (Show, Eq)


-- | When a witness exists in the program it guarantees that a
--   certain property of the program is true.
data Witness a n
        = WAnnot a (Witness a n)

        -- | Witness variable.
        | WVar  !(Bound n)

        -- | Witness constructor.
        | WCon  !(WiCon n)

        -- | Witness application.
        | WApp  !(Witness a n) !(Witness a n)

        -- | Type can appear as the argument of an application.
        | WType !(Type n)
        deriving (Show, Eq)


-- | Type casts.
data Cast a n
        -- | Weaken the effect of an expression.
        --   The given effect is added to the effect
        --   of the body.
        = CastWeakenEffect  !(Effect n)

        -- | Purify the effect (action) of an expression.
        | CastPurify        !(Witness a n)

        -- | Box up a computation,
        --   capturing its effects in the S computation type.
        | CastBox

        -- | Run a computation,
        --   releasing its effects into the environment.
        | CastRun
        deriving (Show, Eq)


-- NFData ---------------------------------------------------------------------
instance (NFData a, NFData n) => NFData (Exp a n) where
 rnf xx
  = case xx of
        XAnnot a x      -> rnf a   `seq` rnf x
        XVar   u        -> rnf u
        XPrim  _        -> ()
        XCon   dc       -> rnf dc
        XLAM   b x      -> rnf b   `seq` rnf x
        XLam   b x      -> rnf b   `seq` rnf x
        XApp   x1 x2    -> rnf x1  `seq` rnf x2
        XLet   lts x    -> rnf lts `seq` rnf x
        XCase  x alts   -> rnf x   `seq` rnf alts
        XCast  c x      -> rnf c   `seq` rnf x
        XType  t        -> rnf t
        XWitness w      -> rnf w


instance (NFData a, NFData n) => NFData (Cast a n) where
 rnf cc
  = case cc of
        CastWeakenEffect e      -> rnf e
        CastPurify w            -> rnf w
        CastBox                 -> ()
        CastRun                 -> ()


instance (NFData a, NFData n) => NFData (Lets a n) where
 rnf lts
  = case lts of
        LLet b x                -> rnf b `seq` rnf x
        LRec bxs                -> rnf bxs
        LPrivate bs1 t2 bs3     -> rnf bs1  `seq` rnf t2 `seq` rnf bs3


instance (NFData a, NFData n) => NFData (Alt a n) where
 rnf aa
  = case aa of
        AAlt w x                -> rnf w `seq` rnf x


instance NFData n => NFData (Pat n) where
 rnf pp
  = case pp of
        PDefault                -> ()
        PData dc bs             -> rnf dc `seq` rnf bs


instance (NFData a, NFData n) => NFData (Witness a n) where
 rnf ww
  = case ww of
        WAnnot a w              -> rnf a `seq` rnf w
        WVar   u                -> rnf u
        WCon   c                -> rnf c
        WApp   w1 w2            -> rnf w1 `seq` rnf w2
        WType  t                -> rnf t

