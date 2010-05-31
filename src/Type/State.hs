-- | Type inferencer state.
module Type.State
	( SquidM
	, SquidS (..)
	, squidSInit
	, getsRef
	, writesRef
	, modifyRef
	, module Type.Base
	, traceM, traceI, traceIE, traceIL
	, instVar
	, newVarN
	, lookupSigmaVar
	, addErrors 
	, gotErrors
	, pathEnter
	, pathLeave
	, graphInstantiatesAdd )
where
import Constraint.Exp
import Type.Error
import Type.Base
import Util
import System.IO
import DDC.Solve.InstanceInfo
import DDC.Type.Exp
import DDC.Var
import DDC.Main.Pretty
import DDC.Main.Error
import Constraint.Pretty	()
import DDC.Main.Arg		(Arg)
import qualified DDC.Main.Arg	as Arg
import qualified Shared.Unique	as U
import qualified Data.Map	as Map
import qualified Util.Data.Map	as Map
import qualified Data.Set	as Set
import Data.IORef

-----
stage	= "Type.State"

-----
type SquidM	= StateT SquidS IO

data SquidS 
	= SquidS
	{ 
	-- | Where to write the trace of what the solver's doing.
	  stateTrace		:: Maybe Handle			
	, stateTraceIndent	:: Int

	-- | Errors encountered whilst solving the constraints.
	, stateErrors		:: [Error]

	-- | Signals that we should stop the solver and not process the next constraint
	--	Useful during debugging, not used otherwise.
	, stateStop		:: Bool 

	-- | The args from the command line
	, stateArgs		:: Set Arg	

	-- | Map of value variables to type variables.
	, stateSigmaTable	:: IORef (Map Var Var)

	-- | Type vars of value vars bound at top level.
	--	Free regions in the types of top level bindings default to be constant.
	, stateVsBoundTopLevel	:: IORef (Set Var)
	
	-- | New variable generator.
	, stateVarGen		:: IORef (Map NameSpace VarId)

	-- | Variable substitution.	
	, stateVarSub		:: IORef (Map Var Var)

	-- | The type graph
	, stateGraph		:: IORef Graph

	-- | Type definitons from CDef constraints.
	--	Most of these won't be used in any particular program and we don't want to pollute
	--	the type graph with this information, nor have to extract them back from the graph
	--	when it's time to export types to the Desugar->Core transform.
	, stateDefs		:: IORef (Map Var Type)

	-- | The current path we've taken though the branches.
	--	This tells us what branch we're currently in, and by tracing
	--	through the path we can work out how a particular variable was bound.
	, statePath		:: IORef [CBind]

	-- | Which branches contain \/ instantiate other branches.
	--	This is used to work out what bindings are part of recursive groups, 
	--	and to determine the type environment for a particular branch when it's 
	--	time to generalise it.
	, stateContains		:: IORef (Map CBind (Set CBind))
	, stateInstantiates	:: IORef (Map CBind (Set CBind))

	-- | Vars of types which are waiting to be generalised.
	--	We've seen a CGen telling us that all the constraints for the type are in 
	--	the graph, but we haven't done the generalisation yet. If this binding is
	--	part of a recursive group then it won't be safe to generalise it until we're
	--	out of that group.
	, stateGenSusp		:: IORef (Set Var)

	-- | Vars of types which have already been generalised 
	--	When we want to instantiate the type for one of the vars in this set then
	--	we can just extract it from the graph, nothing more to do.
	, stateGenDone		:: IORef (Set Var)

	-- | Records how each scheme was instantiated.
	--	We need this to reconstruct the type applications during conversion to
	--	the Core IR.
	, stateInst		:: IORef (Map Var (InstanceInfo Var))

	-- | Records what vars have been quantified. (with optional :> bounds)
	--	After the solver is finished and all generalisations have been performed,
	--	all effect and closure ports will be in this set. We can then clean out
	--	non-ports while we extract them from the graph.
	, stateQuantifiedVarsKM	:: Map Var (Kind, Maybe Type)

	-- | We sometimes need just a set of quantified vars, 
	--	and maintaining this separately from the above stateQuanfiedVarsFM is faster.
	, stateQuantifiedVars	:: Set Var
									
	-- | The projection dictionaries
	--	ctor name -> (type, field var -> implemenation var)
	, stateProject		:: Map Var	(Type, Map Var Var)	
	
	-- | When projections are resolved, Crush.Proj adds an entry to this table mapping the tag
	--	var in the constraint to the instantiation var. We need this in Desugar.ToCore to rewrite
	--	projections to the appropriate function call.
	, stateProjectResolve	:: Map Var Var
									
	-- | Instances for type classses
	--	class name -> instances for this class.
	--   eg Num	   -> [Num (Int %_), Num (Int32# %_)]
	, stateClassInst	:: Map Var 	[Fetter] }


-- | build an initial solver state
squidSInit :: IO SquidS
squidSInit
 = do	let Just tT	= lookup NameType 	U.typeSolve
	let Just rT	= lookup NameRegion 	U.typeSolve
	let Just eT	= lookup NameEffect	U.typeSolve
	let Just cT 	= lookup NameClosure	U.typeSolve
   
	let varGen	= Map.insert NameType    (VarId tT 0)
			$ Map.insert NameRegion  (VarId rT 0)
			$ Map.insert NameEffect  (VarId eT 0)
			$ Map.insert NameClosure (VarId cT 0)
			$ Map.empty 

	refSigmaTable	<- liftIO $ newIORef Map.empty
	refVsBoundTop	<- liftIO $ newIORef Set.empty
	refVarGen	<- liftIO $ newIORef varGen
	refVarSub	<- liftIO $ newIORef Map.empty

	graph		<- graphInit
   	refGraph	<- liftIO $ newIORef graph
   
	refDefs		<- liftIO $ newIORef Map.empty
	refPath		<- liftIO $ newIORef []
	refContains	<- liftIO $ newIORef Map.empty
	refInstantiates	<- liftIO $ newIORef Map.empty
	refGenSusp	<- liftIO $ newIORef Set.empty
	refGenDone	<- liftIO $ newIORef Set.empty
	refGenInst	<- liftIO $ newIORef Map.empty

   	return	SquidS
		{ stateTrace		= Nothing
		, stateTraceIndent	= 0
		, stateArgs		= Set.empty
		, stateSigmaTable	= refSigmaTable
		, stateVsBoundTopLevel	= refVsBoundTop
		, stateVarGen		= refVarGen
		, stateVarSub		= refVarSub
		, stateGraph		= refGraph
		, stateDefs		= refDefs
		, statePath		= refPath
		, stateContains		= refContains
		, stateInstantiates	= refInstantiates
		, stateGenSusp		= refGenSusp
		, stateGenDone		= refGenDone
		, stateInst		= refGenInst
		, stateQuantifiedVarsKM	= Map.empty
		, stateQuantifiedVars	= Set.empty
		, stateProject		= Map.empty
		, stateProjectResolve	= Map.empty
		, stateClassInst	= Map.empty
		, stateErrors		= []
		, stateStop		= False }

getsRef :: (SquidS -> IORef a) -> SquidM a
{-# INLINE getsRef #-}
getsRef getRef
 = do	ref	<- gets getRef
	liftIO	$ readIORef ref

writesRef :: (SquidS -> IORef a) -> a -> SquidM ()
{-# INLINE writesRef #-}
writesRef getRef x
 = do	ref	<- gets getRef
	liftIO	$ writeIORef ref x

modifyRef :: (SquidS -> IORef a) -> (a -> a) -> SquidM ()
{-# INLINE modifyRef #-}
modifyRef getRef fn
 = do	ref	<- gets getRef
	liftIO	$ modifyIORef ref fn


-- | Add some stuff to the inferencer trace.
traceM :: PrettyM PMode -> SquidM ()
traceM p
 = do	mHandle	<- gets stateTrace
	i	<- gets stateTraceIndent
	args	<- gets stateArgs
 	case mHandle of
	 Nothing	-> return ()
	 Just handle
	  -> do 
	  	liftIO (hPutStr handle $ indentSpace i 
				$ pprStr (catMaybes $ map Arg.takePrettyModeOfArg $ Set.toList args) p)
	  	liftIO (hFlush  handle)

	
-- | Do some solver thing, while indenting anything it adds to the trace.
traceI :: SquidM a -> SquidM a
traceI fun
 = do	traceIE
 	x	<- fun
	traceIL
	return x

traceIE :: SquidM ()
traceIE
 = modify (\s -> s { stateTraceIndent = stateTraceIndent s + 4 })
 
traceIL :: SquidM ()
traceIL
 = modify (\s -> s { stateTraceIndent = stateTraceIndent s - 4 })
 
 
-- | Instantiate a variable.
instVar :: Var -> SquidM (Maybe Var)
instVar var
 = do	let space	= varNameSpace var

	-- lookup the generator for this namespace
	varGen		<- getsRef stateVarGen
	let mVarId	= Map.lookup space varGen
	instVar' var space mVarId

instVar' var space mVarId
  	| Nothing	<- mVarId
	= freakout stage
	  	("instVar: can't instantiate var in space " % show space
	  	% " var = " % show var)
		$ return Nothing
		
	| Just vid	<- mVarId
	= do
		-- increment the generator and write it back into the table.
		let vid'	= incVarId vid

		stateVarGen `modifyRef`
			\varGen -> Map.insert space vid' varGen

		-- the new variable remembers what it's an instance of..
		let name	= pprStrPlain vid
		let var'	= (varWithName name)
			 	{ varNameSpace	= varNameSpace var
			 	, varId		= vid }

		return $ Just var'
	

-- | Make a new variable in this namespace
newVarN :: NameSpace ->	SquidM Var
newVarN	space	
 = do
 	Just vid	<- liftM (Map.lookup space)
			$  getsRef stateVarGen
	
	let vid'	= incVarId vid

	stateVarGen `modifyRef` \varGen -> 
		Map.insert space vid' varGen
	
	let name	= pprStrPlain vid
	let var'	= (varWithName name)
			{ varNameSpace	= space 
			, varId		= vid }
			
	return var'


-- | Lookup the type variable corresponding to this value variable.
lookupSigmaVar :: Var -> SquidM (Maybe Var)
lookupSigmaVar	v
 	= liftM (Map.lookup v)
	$ getsRef stateSigmaTable
	
	
-- | Add some errors to the monad.
--	These'll be regular user-level type errors from the compiled program.
addErrors ::	[Error]	-> SquidM ()
addErrors	errs
	= modify (\s -> s { stateErrors = stateErrors s ++ errs })


-- | See if there are any errors in the state
gotErrors :: SquidM Bool
gotErrors
 = do	errs	<- gets stateErrors
 	return	$ not $ isNil errs


-- | Push a new var on the path queue.
--	This records the fact that we've entered a branch.
pathEnter :: CBind -> SquidM ()
pathEnter BNothing	= return ()
pathEnter v	
	= statePath `modifyRef` \path -> v : path 


-- | Pop a var off the path queue
--	This records the fact that we've left the branch.
pathLeave :: CBind -> SquidM ()
pathLeave BNothing	= return ()
pathLeave bind
  = statePath `modifyRef` \path ->
	case path of
	  	-- pop matching binders off the path
		b1 : bs
		 | bind == b1	-> bs
	
		-- nothing matched.. :(
		_ -> panic stage $ "pathLeave: can't leave " % bind % "\n"

		
-- | Add to the who instantiates who list
graphInstantiatesAdd :: CBind -> CBind -> SquidM ()
graphInstantiatesAdd    vBranch vInst
 = stateInstantiates `modifyRef` \instantiates -> 
	Map.adjustWithDefault 
		(Set.insert vInst) 
		Set.empty
		vBranch
		instantiates

