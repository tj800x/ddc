
module DDC.Core.Flow.Prim.OpFlow
        ( readOpFlow
        , typeOpFlow
        , xRateOfSeries
        , xNatOfRateNat)
where
import DDC.Core.Flow.Prim.KiConFlow
import DDC.Core.Flow.Prim.TyConFlow
import DDC.Core.Flow.Prim.TyConPrim
import DDC.Core.Flow.Prim.Base
import DDC.Core.Transform.LiftT
import DDC.Core.Compounds.Simple
import DDC.Core.Exp.Simple
import DDC.Base.Pretty
import Control.DeepSeq
import Data.List
import Data.Char        


instance NFData OpFlow


instance Pretty OpFlow where
 ppr pf
  = case pf of
        OpFlowVectorOfSeries    -> text "vectorOfSeries"        <> text "#"
        OpFlowRateOfSeries      -> text "rateOfSeries"          <> text "#"
        OpFlowNatOfRateNat      -> text "natOfRateNat"          <> text "#"

        OpFlowMkSel n           -> text "mkSel"      <> int n   <> text "#"

        OpFlowMap i             -> text "map"        <> int i   <> text "#"

        OpFlowRep               -> text "rep"                   <> text "#"
        OpFlowReps              -> text "reps"                  <> text "#"

        OpFlowFold              -> text "fold"                  <> text "#"
        OpFlowFoldIndex         -> text "foldIndex"             <> text "#"
        OpFlowFolds             -> text "folds"                 <> text "#"

        OpFlowUnfold            -> text "unfold"                <> text "#"
        OpFlowUnfolds           -> text "unfolds"               <> text "#"

        OpFlowSplit   i         -> text "split"      <> int i   <> text "#"
        OpFlowCombine i         -> text "combine"    <> int i   <> text "#"

        OpFlowPack              -> text "pack"                  <> text "#"


-- | Read a data flow operator name.
readOpFlow :: String -> Maybe OpFlow
readOpFlow str
        | Just rest     <- stripPrefix "mkSel" str
        , (ds, "#")     <- span isDigit rest
        , not $ null ds
        , arity         <- read ds
        = Just $ OpFlowMkSel arity

        | Just rest     <- stripPrefix "map" str
        , (ds, "#")     <- span isDigit rest
        , not $ null ds
        , arity         <- read ds
        = Just $ OpFlowMap arity

        | Just rest     <- stripPrefix "split" str
        , (ds, "#")     <- span isDigit rest
        , not $ null ds
        , arity         <- read ds
        = Just $ OpFlowSplit arity

        | Just rest     <- stripPrefix "combine" str
        , (ds, "#")     <- span isDigit rest
        , not $ null ds
        , arity         <- read ds
        = Just $ OpFlowCombine arity

        | otherwise
        = case str of
                "vectorOfSeries#"  -> Just $ OpFlowVectorOfSeries
                "rateOfSeries#"    -> Just $ OpFlowRateOfSeries
                "natOfRateNat#"    -> Just $ OpFlowNatOfRateNat
                "map#"             -> Just $ OpFlowMap 1
                "rep#"             -> Just $ OpFlowRep
                "reps#"            -> Just $ OpFlowReps
                "fold#"            -> Just $ OpFlowFold
                "foldIndex#"       -> Just $ OpFlowFoldIndex
                "folds#"           -> Just $ OpFlowFolds
                "unfold#"          -> Just $ OpFlowUnfold
                "unfolds#"         -> Just $ OpFlowUnfolds
                "pack#"            -> Just $ OpFlowPack
                _                  -> Nothing


-- Types -----------------------------------------------------------------------
-- | Yield the type of a data flow operator.
typeOpFlow :: OpFlow -> Type Name
typeOpFlow op
 = case op of
        -- Series Conversions -------------------
        -- vectorOfSeries# :: [k : Rate]. [a : Data]
        --                 .  Series k a -> Vector a
        OpFlowVectorOfSeries
         -> tForalls [kRate, kData]
         $  \[tK, tA] -> tSeries tK tA `tFunPE` tVector tA

        -- rateOfSeries#   :: [k : Rate]. [a : Data]
        --                 .  Series k a -> RateNat k
        OpFlowRateOfSeries 
         -> tForalls [kRate, kData]
         $  \[tK, tA]
                -> tSeries tK tA `tFunPE` tRateNat tK

        -- natOfRateNat#   :: [k : Rate]. RateNat k -> Nat#
        OpFlowNatOfRateNat 
         -> tForall kRate
         $  \tK -> tRateNat tK `tFunPE` tNat


        -- Selectors ----------------------------
        -- mkSel1#    :: [k1 : Rate]. [a : Data]
        --            .  Series k1 Bool#
        --            -> ([k2 : Rate]. Sel1 k1 k2 -> a)
        --            -> a
        OpFlowMkSel 1
         -> tForalls [kRate, kData]
         $  \[tK1, tA]
         -> tSeries tK1 tBool
                `tFunPE` (tForall kRate $ \tK2 
                                -> tSel1 (liftT 1 tK1) tK2 `tFunPE` (liftT 1 tA))
                `tFunPE` tA

        -- Maps ---------------------------------
        -- map   :: [k : Rate] [a b : Data]
        --       .  (a -> b) -> Series k a -> Series k b
        OpFlowMap 1
         -> tForalls [kRate, kData, kData]
         $  \[tK, tA, tB]
         -> (tA `tFunPE` tB)
                `tFunPE` tSeries tK tA
                `tFunPE` tSeries tK tB

        -- map2  :: [k : Rate] [a b c : Data]
        --       .  (a -> b -> c) -> Series k a -> Series k b -> Series k c
        -- TODO generalise
        OpFlowMap 2
         -> tForalls [kRate, kData, kData, kData]
         $  \[tK, tA, tB, tC]
         -> (tA `tFunPE` tB `tFunPE` tC)
                `tFunPE` tSeries tK tA
                `tFunPE` tSeries tK tB
                `tFunPE` tSeries tK tC



        -- Replicates -------------------------
        -- rep  :: [a : Data] [k : Rate]
        --      .  a -> Series k a
        OpFlowRep 
         -> tForalls [kData, kRate]
         $  \[tA, tR]
         ->     tA `tFunPE` tSeries tR tA


        -- reps  :: [k1 k2 : Rate]. [a : Data]
        --       .  Segd   k1 k2 
        --       -> Series k1 a
        --       -> Series k2 a
        OpFlowReps 
         -> tForalls [kRate, kRate, kData]
         $  \[tK1, tK2, tA]
         -> tSegd tK1 tK2
                `tFunPE` tSeries tK1 tA
                `tFunPE` tSeries tK2 tA

        -- fold :: [k : Rate]. [a b: Data]
        --      .  (a -> b -> a) -> a -> Series k b -> a
        OpFlowFold    
         -> tForalls [kRate, kData, kData] 
         $  \[tK, tA, tB]
         -> (tA `tFunPE` tB `tFunPE` tA)
                `tFunPE` tA
                `tFunPE` tSeries tK tB
                `tFunPE` tA

        -- foldIndex :: [k : Rate]. [a b: Data]
        --           .  (Int# -> a -> b -> a) -> a -> Series k b -> a
        OpFlowFoldIndex
         -> tForalls [kRate, kData, kData] 
         $  \[tK, tA, tB]
         -> (tInt `tFunPE` tA `tFunPE` tB `tFunPE` tA)
                `tFunPE` tA
                `tFunPE` tSeries tK tB
                `tFunPE` tA

        -- folds :: [k1 k2 : Rate]. [a b: Data]
        --       .  Segd   k1 k2 
        --       -> (a -> b -> a)       -- fold operator
        --       -> Series k1 a         -- start values
        --       -> Series k2 b         -- source elements
        --       -> Series k1 a         -- result values
        OpFlowFolds
         -> tForalls [kRate, kRate, kData, kData]
         $  \[tK1, tK2, tA, tB]
         -> tSegd tK1 tK2
                `tFunPE` (tInt `tFunPE` tA `tFunPE` tB `tFunPE` tA)
                `tFunPE` tSeries tK1 tA
                `tFunPE` tSeries tK2 tB
                `tFunPE` tSeries tK1 tA

        -- pack  :: [k1 k2 : Rate]. [a : Data]
        --       .  Sel2 k1 k2
        --       -> Series k1 a -> Series k2 a
        OpFlowPack
         -> tForalls [kRate, kRate, kData]
         $  \[tK1, tK2, tA]
         -> tSel1 tK1 tK2 
                `tFunPE` tSeries tK1 tA
                `tFunPE` tSeries tK2 tA

        _ -> error $ unlines
                   [ "ddc-core-flow.typeOpFlow"
                   , "    Not finished for " ++ show op ]


-- Compounds ------------------------------------------------------------------
xRateOfSeries :: Type Name -> Type Name -> Exp () Name -> Exp () Name
xRateOfSeries tK tA xS 
         = xApps  (xVarOpFlow OpFlowRateOfSeries) 
                  [XType tK, XType tA, xS]


xNatOfRateNat :: Type Name -> Exp () Name -> Exp () Name
xNatOfRateNat tK xR
        = xApps  (xVarOpFlow OpFlowNatOfRateNat)
                 [XType tK, xR]


-- Utils -----------------------------------------------------------------------
xVarOpFlow :: OpFlow -> Exp () Name
xVarOpFlow op
        = XVar  (UPrim (NameOpFlow op) (typeOpFlow op))

