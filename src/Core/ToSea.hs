
-- | Convert CoreIR to Abstract-C
module Core.ToSea
	( toSeaTree 
	, superOpTypeP
	, superOpTypeX)

where
import qualified Core.Exp 		as C
import qualified Core.Util		as C
import qualified Core.Pretty		as C
import qualified Core.Util		as C
import qualified Core.Util.Slurp	as C
import qualified Core.Reconstruct	as C

import qualified Type.Exp		as T
import qualified Type.Util		as T

import qualified Sea.Exp  		as E
import qualified Sea.Util		as E
import qualified Sea.Pretty		as E

import Shared.Var			(Var, NameSpace(..))
import Shared.Error
import Shared.Base
import Shared.Pretty
import Shared.Literal
import Shared.VarUtil			(prettyPos)
import qualified Shared.VarBind		as Var
import qualified Shared.Unique		as Unique
import qualified Shared.Var		as Var
import qualified Shared.VarPrim		as Var

import Util
import Data.Map				(Map)
import Data.Set				(Set)
import Control.Monad.State
import qualified Data.Map		as Map
import qualified Data.Set		as Set
import qualified			Debug.Trace


-----
stage	= "Core.ToSea"
{-
debug	= True
trace ss x	
	= if debug 
		then Debug.Trace.trace (pprStrPlain ss) x
		else x
-}

-- State -------------------------------------------------------------------------------------------
data SeaS
	= SeaS
	{ -- variable name generator
	  stateVarGen		:: Var.VarBind

	  -- constructor definitions
	, stateCtorDefs		:: Map Var C.CtorDef 

	  -- regions known to be direct
	, stateDirectRegions	:: Set Var }

type SeaM	= State SeaS
	
newVarN ::	NameSpace -> SeaM Var
newVarN		space
 = do 	varBind		<- gets stateVarGen
	let varBind'	= Var.incVarBind varBind
	modify (\s -> s { stateVarGen = varBind' })

	let var		= (Var.new $ pprStrPlain varBind)
			{ Var.bind	= varBind
			, Var.nameSpace	= space }
	return var


-- | If this is a witness to constness of a region or type, or purity of an effect
--	then slurp it into the table.
slurpWitnessKind 
	:: C.Kind -> SeaM ()

slurpWitnessKind kk
 = case kk of
	-- const regions
 	C.KClass C.TyClassDirect [C.TVar C.KRegion r]
	 -> modify $ \s -> s { stateDirectRegions 
		 		= Set.insert r (stateDirectRegions s) }

	_ -> return ()


-- Tree --------------------------------------------------------------------------------------------
toSeaTree 
	:: String		-- unique
	-> Map Var C.CtorDef	-- Map of Constructor Definitions.
				--	Used for converting field label projections
				--	to projections field index projections.
	-> C.Tree
	-> E.Tree ()
	
toSeaTree unique mapCtorDefs cTree
  = evalState
  	(liftM concat $ mapM toSeaP cTree)
	SeaS 	{ stateVarGen		= Var.XBind ("x" ++ unique) 0
		, stateCtorDefs		= mapCtorDefs 
		, stateDirectRegions	= Set.empty }
    
    
-- Top ---------------------------------------------------------------------------------------------
toSeaP :: C.Top -> SeaM [E.Top ()]
toSeaP	xx
 = case xx of
	
	-- region
	--	slurp witnesses on the way down
	C.PRegion v vts
	 -> do	let Just ks	= sequence $ map (T.kindOfType . snd) vts
	 	mapM_ slurpWitnessKind ks
	 	return	[]

	C.PExtern{}
	 ->	return []
	 	 
 	C.PBind v x
	 -> do	let to		= superOpTypeX x

		let (argTypes, resultType)	
				= splitOpType to

		-- split the RHS into its value args and expression
	 	(argNames, exp)	
				<- splitSuper [] x
		
		sss'		<- mapM toSeaS $ slurpStmtsX exp
		let ss'		= concat sss'
		let argNTs	= zip argNames argTypes

		retV		<- newVarN NameValue
		let ssRet	= assignLastSS (E.XVar retV, resultType) ss'
				++ [E.SReturn (E.XVar retV)]
		
	   	return	$ case argNTs of
			    	 [] ->	[ E.PCafProto	v
					, E.PCafSlot 	v
					, E.PSuper	v [] 	resultType  ssRet]

				 _ ->	[ E.PSuper 	v argNTs resultType ssRet]
	    
	C.PData v ts cs
	 -> do	cs'		<- mapM toSeaCtor cs
	 	let dataDef	= E.PData v cs'
	 	let tagDefs	= map (\(v, i) -> E.PHashDef 
			 		("_tag" ++ E.seaVar False v)
					("(_tagBase + " ++ show i ++ ")"))
				$ (zip (map (\(C.CtorDef v _) -> v) cs) [0..])
	 
		let structDefs	= map toSeaStruct cs
		return		$ [dataDef] ++ tagDefs ++ structDefs
	 
	   		
	_ ->	return []


-- | split the RHS of a supercombinator into its args and expression
splitSuper :: [C.Var] -> C.Exp -> SeaM ([C.Var], C.Exp)
splitSuper accArgs xx

	| C.XLam v t x eff clo	<- xx
	= splitSuper (accArgs ++ [v]) x
	
	| C.XLAM v k x		<- xx
	= do	slurpWitnessKind k
		splitSuper accArgs x

	| C.XTau t x		<- xx
	= splitSuper accArgs x
	
	| C.XTet vts x		<- xx
	= 	splitSuper accArgs x
	
	| C.XLocal v vts x	<- xx
	= do	let Just ks	= sequence $ map (T.kindOfType . snd) vts
		mapM_ slurpWitnessKind ks
		splitSuper accArgs x
	
	| otherwise
	= return (accArgs, xx)	 



-- CtorDef -----------------------------------------------------------------------------------------
toSeaStruct 
	:: C.CtorDef
	-> E.Top ()

toSeaStruct (C.CtorDef name fs)
	= E.PStruct name
	$ map (\(i, df) -> 
		( fromMaybe (Var.new $ "a" ++ show i) $ C.dLabel df
		, E.TObj )) -- toSeaT $ C.dType df ))
	$ zip [0..] fs


-- Ctor --------------------------------------------------------------------------------------------
toSeaCtor 
	:: C.CtorDef
	-> SeaM (Var, [E.DataField E.Var E.Type])
	
toSeaCtor (C.CtorDef name fs)
 = do
 	fs'	<- mapM toSeaDataField fs
	return	$ (name, fs')
	

-- DataField ---------------------------------------------------------------------------------------
toSeaDataField
	:: C.DataField C.Var C.Type
	-> SeaM (E.DataField E.Var E.Type)
	
toSeaDataField field
 = do	mInit	<- case C.dInit field of
 			Nothing		-> return $ Nothing
			Just x		-> return $ Just x		
				
	return	E.DataField
		{ E.dPrimary	= C.dPrimary 	field
		, E.dLabel	= C.dLabel	field
		, E.dType	= E.TObj
		, E.dInit	= mInit }


-- Exp ---------------------------------------------------------------------------------------------
toSeaX	:: C.Exp -> SeaM (E.Exp ())
toSeaX		xx
 = case xx of
	C.XVar v t
	 -> return $ E.XVar v

	-- discard left over annots
	C.XAnnot  n x		-> toSeaX x
	C.XTau    t x		-> toSeaX x
	C.XTet    vts x		-> toSeaX x

	-- slurp region witnesses on the way down
	C.XLocal  v vts x	
	 -> do	let Just ks	= sequence $ map (T.kindOfType . snd) vts
	 	mapM_ slurpWitnessKind ks
	 	toSeaX x

	-- slurp region witnesses on the way down
	C.XLAM v k x
	 -> do 	slurpWitnessKind k
	 	toSeaX x

	-- function calls
	C.XPrim C.MTailCall xs
	 -> do	let (C.XVar v _) : args	= stripValues xs
		args'	<- mapM toSeaX args
		return	$ E.XTailCall v args'

	C.XPrim C.MCall xs
	 -> do	let (C.XVar v _) : args	= stripValues xs
		args'	<- mapM toSeaX args
	    	return	$ E.XCall v args'

	C.XPrim (C.MCallApp superA) xs
	 -> do	let (C.XVar v _) : args	= stripValues xs
		args'	<- mapM toSeaX args
		return	$ E.XCallApp v superA args'

	C.XPrim C.MApply xs
	 -> do	let (C.XVar v _) : args	= stripValues xs
		args'	<- mapM toSeaX args
	    	return	$ E.XApply (E.XVar v) args'
	   
	C.XPrim (C.MCurry superA) xs
	 -> do	let (C.XVar v _) : args	= stripValues xs
		if any isUnboxed args
                 then panic stage $ "Partial application of function to unboxed args at " % prettyPos v
                 else
		  do	args'	<- mapM toSeaX args
			return	$ E.XCurry v superA args'

	C.XPrim (C.MFun) xs
	 -> do	let (C.XVar v _) : args	= stripValues xs
		args'	<- mapM toSeaX args
		return	$ E.XPrim (toSeaPrimV v) args'

	C.XPrim (C.MOp op) xs
	 -> do	let args		= stripValues xs
		args'	<- mapM toSeaX args
		return	$ E.XPrim (toSeaOp op) args'

	-- suspend
	C.XPrim (C.MSuspend fn)	args 
	 -> do	let args'	= map E.XVar 
		 		$ filter (\v -> Var.nameSpace v == NameValue) 
				$ map (\(C.XVar v t) -> v)
		 		$ args

		return	$ E.XSuspend fn args'

	-- boxing
	C.XPrim C.MBox [_, x]
	 -> do	let t	= C.reconX_type (stage ++ "toSeaX") x
		x'	<- toSeaX x

		return	$ E.XBox (toSeaT t) x'

	-- the unboxing function is named after the result type
	C.XPrim C.MUnbox [C.XType r, x]
	 -> do	let tResult	= C.reconUnboxType r 
	 			$ C.reconX_type (stage ++ "toSeaX") x

		x'	<- toSeaX x

		return	$ E.XUnbox (toSeaT tResult) x'

	-- forcing
	C.XPrim (C.MForce) [x]
	 -> do	x'	<- toSeaX x
	 	return	$ E.XForce x'


	C.XAtom v ts
	 -> return	$ E.XAtom v

	-- non string constants
	C.XLit litFmt@(LiteralFmt lit fmt)
	 | dataFormatIsBoxed fmt
	 -> panic stage $ "toSeaX[XLit]: can't convert boxed literal " % litFmt
	 
	 | otherwise
	 -> return	$ E.XLit litFmt

	-- string constants are always applied to regions 
	C.XAPP (C.XLit litFmt@(LiteralFmt l@LString{} fmt)) (C.TVar C.KRegion r)
	 -> return	$ E.XLit litFmt

	-- An application to type/region/effects only
	--	we can just discard the TRE applications and keep the value.
	C.XAPP{}
	 -> let
	 	parts		= C.flattenApps xx
		(C.XVar vF _ : _)	= parts
		
	    in 	return	$ E.XVar vF
	 	
	_ -> panic stage
		$ "toSeaX: cannot convert expression to Sea IR.\n" 
		% "-----\n"
		% xx					% "\n"


isUnboxed :: C.Exp -> Bool
isUnboxed x
 = case x of
	-- This may not be complete.
	C.XLit (LiteralFmt _ fmt) -> dataFormatIsUnboxed fmt
	_ -> False

-- Stmt --------------------------------------------------------------------------------------------
-- | Convert a statement into Sea
--
--   In the core, the RHS of a stmt might be another do, but there won't be any value
--   lambdas in front of it due to lambda lifting.
--
--   eg:  s = /\ +w13 :: Mutable %r1
--            [** type] 
--            do { ... }
--
--   The Sea code doesn't handle nested groups of statements, but we can flatten them
--   all out into a single list here.
--	
--
toSeaS	:: C.Stmt -> SeaM [E.Stmt ()]
toSeaS xx
 = case xx of
	-- decend past type info
	C.SBind b (C.XTau t x)
	 -> toSeaS $ C.SBind b x
	 
	C.SBind b (C.XLAM v k x)
	 -> toSeaS $ C.SBind b x

	C.SBind b (C.XLocal v vts x)
	 -> toSeaS $ C.SBind b x


	-- do
	-- flatten out the initial statements and recursively bind the lhs 
	--	to the last expression in the list.
	C.SBind b (C.XDo ss)
	 -> do  let Just ssInit			= takeInit ss
	 	let Just (C.SBind Nothing x) 	= takeLast ss
		
		ssInit'	<- liftM concat $ mapM toSeaS ssInit
		ssMore	<- toSeaS (C.SBind b x)
		
	    	return	$ ssInit' ++ ssMore

	-- matches
	C.SBind (Just v) x@(C.XMatch aa)
	 -> do	aa'		<- mapM (toSeaA Nothing) aa

		let xT		= C.reconX_type (stage ++ ".toSeaS") x
		let t		= toSeaT xT
		let aaL		= map (assignLastA (E.XVar v, t)) aa'
		
		return		[E.SMatch aaL]


	C.SBind Nothing	x@(C.XMatch aa)
	 -> do	aa'		<- mapM (toSeaA Nothing) aa
	    	return		[E.SMatch aa']

	    
	-- expressions
	C.SBind (Just v) x
	 -> do	x'		<- toSeaX $ C.slurpExpX x
		let t		= C.reconX_type (stage ++ ".toSeaS") x
	    	return		[E.SAssign (E.XVar v) (toSeaT t) x']

	C.SBind Nothing x
	 -> do	x'		<- toSeaX x
	    	return		[E.SStmt x']


-- Alt ---------------------------------------------------------------------------------------------
toSeaA :: (Maybe C.Exp) -> C.Alt -> SeaM (E.Alt ())
toSeaA	   mObjV xx
 = case xx of
	C.AAlt [] x
	 -> do	
	 	ss'		<- liftM concat
				$  mapM toSeaS
				$  slurpStmtsX x
	 
	    	return	$ E.ADefault ss'

	C.AAlt gs x
	 -> do	(ssFront, mgs')	<- mapAccumLM (toSeaG mObjV) [] gs
		let gs'		= catMaybes mgs'

	    	ss'		<- liftM concat
				$  mapM toSeaS
				$  slurpStmtsX x
		
		return	$ E.AAlt gs' (ssFront ++ ss')
				
	


-- Guard -------------------------------------------------------------------------------------------
toSeaG	:: Maybe C.Exp 		-- match object
	-> [E.Stmt ()] 		-- stmts to add to the front of this guard.
	-> C.Guard 
	-> SeaM ( [E.Stmt ()]	-- stmts to add to the front of the next guard.
		,  Maybe (E.Guard ()))


toSeaG	mObjV ssFront gg
 = case gg of

	C.GExp w x
	 -> do	-- work out the type of the RHS
	 	let t		= C.reconX_type (stage ++ ".toSeaG") x
		let t'		= toSeaT t
	
	  	-- convert the RHS expression into a sequence of stmts
	 	ssRHS		<- liftM concat
				$  mapM toSeaS
				$  slurpStmtsX x
		

		-- if the guard expression is in a direct region then we don't need to check
		--	for suspensions during the match
		rhsIsDirect	<- isDirectType t

		let result
			-- if the LHS is var we can make the last stmt of the RHS assign it.
			| C.WVar var'	<- w
			= do	let ssL		= assignLastSS (E.XVar var', t') ssRHS
				return	( ssFront ++ ssL
					, Nothing)

			-- the Sea language can't match against boxed literals
			| C.WLit litFmt@(LiteralFmt lit fmt)	<- w
			, dataFormatIsBoxed fmt
			= panic stage 	$ "toSeaG: can't match against boxed data: " % show fmt % "\n"
					% "   when converting guard: " % gg

			-- match against an unboxed literal value
			| C.WLit litFmt@(LiteralFmt lit fmt)	<- w
			, dataFormatIsUnboxed fmt
			= do	var	<- newVarN NameValue

				let compX	= if isPatConst w
					then E.XVar var
					else E.XTag $ E.XVar var

				let ssL		= assignLastSS (E.XVar var, t') ssRHS
				return	( []
					, Just $ E.GCase False (ssFront ++ ssL) compX (E.XLit litFmt))
			  
			-- match against constructor
			| C.WCon v lvts	<- w
			= do	var		<- newVarN NameValue

				let compX	= if isPatConst w
					then E.XVar var
					else E.XTag $ E.XVar var

				let ssL		= assignLastSS (E.XVar var, t') ssRHS
				return	( map (toSeaGL var) lvts
					, Just $ E.GCase (not rhsIsDirect) (ssFront ++ ssL) compX (E.XCon v))

		result


-- check if this type is in a direct region
isDirectType :: C.Type -> SeaM Bool
isDirectType tt
	| Just (v, k, C.TVar C.KRegion vR : _)	<- T.takeTData tt
	= do	directRegions	<- gets stateDirectRegions
	 	return	$ Set.member vR directRegions

	| otherwise
	= 	return False

	
isPatConst gg
 = case gg of
 	C.WLit{}	-> True
	_		-> False


toSeaGL	 objV (label, var, t)
	| C.LIndex i	<- label
	= E.SAssign (E.XVar var) E.TObj (E.XArg (E.XVar objV) E.TData i)


-----
slurpStmtsX :: C.Exp -> [C.Stmt]
slurpStmtsX xx
 = case xx of
 	C.XLocal v vs x	-> slurpStmtsX x
	C.XDo ss	-> ss
	_		-> []


-- Type --------------------------------------------------------------------------------------------

-- | Convert an operational type from the core to the equivalent Sea type.
toSeaT :: C.Type	-> E.Type
toSeaT	xx
	-- Sanity: the type to convert must be a value type.
--	| not $ hasValueKind xx
--	= panic stage 
--		$ "toSeaT: cannot convert non-value type " % xx % " to Sea type\n"
--		% "    kind = " % T.kindOfType xx % "\n"

	-- the unboxed void type is represented directly.
	| Just (v, _, _)	<- T.takeTData xx
	, Var.TVoidU		<- Var.bind v
	= E.TVoid
	
	-- we know about unboxed pointers
	| Just (v, _, [t])	<- T.takeTData xx
	, Var.TPtrU		<- Var.bind v
	= E.TPtr (toSeaT t)
	
	-- the build-in unboxed types are represented directly.
	| Just (v, _, ts)	<- T.takeTData xx
	, Var.varIsUnboxedTyConData v
	= E.TCon v (map toSeaT $ filter hasValueKind ts)
	
	-- some user defined unboxed type.
	-- TODO: we just check for a '#' in the name to detect these, 
	--	 which is pretty nasty. 
	| Just (v, _, ts)	<- T.takeTData xx
	, elem '#' (Var.name v)
	= E.TCon v (map toSeaT $ filter hasValueKind ts)
	
	-- some first class, boxed object
	| otherwise
	= E.TObj

hasValueKind :: C.Type -> Bool
hasValueKind xx
	| Just k	<- T.kindOfType xx
	, not $ elem k [T.KRegion, T.KClosure, T.KEffect]
	= True
	
	| otherwise
	= False

splitOpType to
  = let	opParts		= T.flattenFun to
	opParts'@(_:_)	= map toSeaT opParts
		
	argTypes	= init opParts'
	resultType	= last opParts'
   in 	(argTypes, resultType)


-- | Throw away the type terms in this list of expressions.
stripValues :: [C.Exp] -> [C.Exp]
stripValues args
	= catMaybes 
	$ map stripValues' args

stripValues' a
 = case a of
	C.XVar v t
	 |  Var.nameSpace v /= NameValue
	 -> Nothing

	C.XType _
	 -> Nothing
	 
	_ -> Just a
	 
-----
-- assignLastSS
--	Assign the value of the stmt(s) in this list
--	to the provided exp.
--
assignLastSS :: (E.Exp (), E.Type) -> [E.Stmt ()] -> [E.Stmt ()]
assignLastSS	xT    ss
 = let	Just firstSS	= takeInit ss
 	Just lastS	= takeLast ss

   in	firstSS ++ (assignLastS xT lastS)
	

assignLastS :: (E.Exp (), E.Type) -> E.Stmt () -> [E.Stmt ()]
assignLastS xT@(aX, t) ss
 = case ss of
 	E.SStmt 	x	-> [E.SAssign aX t x]
	E.SAssign 	x _ _ 	-> [ss] ++ [E.SAssign aX t x]
	E.SSwitch       x aa	-> [E.SSwitch x (map (assignLastA xT) aa)]
	E.SMatch 	aa	-> [E.SMatch (map (assignLastA xT) aa)]

    
assignLastA :: (E.Exp (), E.Type) -> E.Alt () -> E.Alt ()
assignLastA xT aa
 = case aa of
 	E.ASwitch x ss		-> E.ASwitch x	(assignLastSS xT ss)
	E.ADefault ss		-> E.ADefault	(assignLastSS xT ss)
	E.AAlt gs ss		-> E.AAlt gs	(assignLastSS xT ss)



-- | Convert a Core operator to a Sea primitive
--	We should perhaps change Sea land to use the core representation
toSeaOp :: C.Op -> E.Prim
toSeaOp op
 = case op of
	-- arithmetic
	C.OpNeg -> E.FNeg
 	C.OpAdd	-> E.FAdd
	C.OpSub	-> E.FSub
	C.OpMul	-> E.FMul
	C.OpDiv	-> E.FDiv
	C.OpMod	-> E.FMod

	-- comparison
	C.OpEq	-> E.FEq
	C.OpNeq	-> E.FNEq
	C.OpGt	-> E.FGt
	C.OpGe	-> E.FGe
	C.OpLt	-> E.FLt
	C.OpLe	-> E.FLe
	
	-- boolean
	C.OpAnd	-> E.FAnd
	C.OpOr	-> E.FOr
	 
	

toSeaPrimV :: C.Var -> E.Prim
toSeaPrimV var
 = case Var.name var of
	"primProjField"		-> E.FProjField
	"primProjFieldR"	-> E.FProjFieldR

	-- array	
	"arrayUI_get"		-> E.FArrayPeek (E.TCon (Var.primTInt (UnboxedBits 32)) [])
	"arrayUI_set"		-> E.FArrayPoke (E.TCon (Var.primTInt (UnboxedBits 32)) [])
	
	_			-> panic stage
				$ "toSeaPrim: no match for " % var



-- superOpType -------------------------------------------------------------------------------------

-- | Work out the operational type of a supercombinator.
--	The operational type of an object different from the value type in two main respects:
--
--	1) The Sea translation doesn't care about alot of the type information present
--	   in the core types. eg boxed objects are just Obj*, and regions aren't used at all
--
--	2) Supercombinators can return function objects, with value type (a -> b), but the 
--	   sea code treats them as just vanilla boxed objects.
--
superOpTypeP ::	 C.Top -> C.Type
superOpTypeP	pp
 = case pp of
 	C.PBind v x
	 -> let	parts	= superOpType' x
	    in	T.makeTFuns_pureEmpty parts

	-- external functions and ctors carry their operational
	--	types around with them.
	C.PExtern v tv to	-> to
	C.PCtor   v tv to	-> to

	_ 	-> panic stage 
		$ "superOpTypeP: no match for " % show pp % "\n"


-- | Work out the operational type of this expression
superOpTypeX :: C.Exp -> C.Type
superOpTypeX	xx
	= T.makeTFuns_pureEmpty $ superOpType' xx

superOpType'	xx
 = case xx of
	-- skip over type information
	C.XLAM    v k x	-> superOpType' x
	C.XTet    vts x	-> superOpType' x

	-- slurp off parameter types
 	C.XLam v t x eff clo 
	 -> superOpTypePart t :  superOpType' x

	-- take the type of the body of the super from the XTau enclosing it.
	C.XTau	t x	-> [superOpTypePart t]
	
	-- there's no XTau enclosing the body, so we'll have to reconstruct
	--	the type for it manually.
	_		-> [superOpTypePart 
			$  C.reconX_type (stage ++ "superOpType") xx]
			
superOpTypePart	tt
 = case tt of
	C.TNil			-> C.TNil

	-- skip over type information
	C.TForall v k t		-> superOpTypePart t
	C.TContext c t		-> superOpTypePart t
	C.TFetters t fs		-> superOpTypePart t

	-- an unboxed var of airity zero, eg Int32#
	C.TCon (C.TyConData name kind)
	 | T.isUnboxedT tt
	 -> T.makeTData name C.KValue []

	-- a tycon of arity zero, eg Unit
	C.TCon (C.TyConData name kind)
	 -> T.makeTData Var.primTData C.KValue []

	C.TApp{}
	 -> let	result	
		 	-- unboxed types are represented directly, and the Sea
			--	code must know about them.
	 		| Just (v, k, ts)	<- T.takeTData tt
			, v == Var.primTPtrU	
			= T.makeTData v k (map superOpTypePart ts)

			-- an unboxed tycon of some aritity, eg String#
			| Just (v, k, ts)	<- T.takeTData tt
			, T.isUnboxedT tt
			= T.makeTData v k []

			-- boxed types are just 'Data'
			| Just (v, k, ts)	<- T.takeTData tt
			= T.makeTData Var.primTData k []
			
			-- all function objects are considered to be 'Thunk'
			| Just _		<- T.takeTFun tt
			= T.makeTData Var.primTThunk C.KValue []
			
			| otherwise
			= T.makeTData Var.primTObj C.KValue []
	   in result			

	-- some unknown, boxed object 'Obj'
	C.TVar C.KValue _	-> T.makeTData Var.primTObj C.KValue []

	_	-> panic stage
		$  "superOpTypePart: no match for " % show tt % "\n"

