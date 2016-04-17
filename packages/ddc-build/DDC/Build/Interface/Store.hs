
module DDC.Build.Interface.Store
        ( Store
        , new, wrap, load

        , Meta  (..)
        , getMeta
        , getModuleNames
        , getInterfaces

        , Super (..)
        , findSuper)
where
import DDC.Build.Interface.Base         
import DDC.Build.Interface.Load
import DDC.Core.Call
import DDC.Core.Module
import DDC.Type.Exp
import System.Directory
import Data.Time.Clock
import Data.IORef
import Data.Maybe
import Data.Map                         (Map)
import qualified DDC.Core.Tetra         as E
import qualified DDC.Core.Salt          as A
import qualified Data.Map               as Map


---------------------------------------------------------------------------------------------------
-- | Abstract API to a collection of module interfaces.
--
--   This lives in IO land because in future we want to demand-load the
--   inferface files as needed, rather than loading the full dependency
--   tree. Keeping it in IO means that callers must also be in IO.
data Store
        = Store
        { -- | Metadata for interface files currently in the store.
          storeMeta     :: IORef [Meta]

          -- | Lookup the definition of the given top-level super, 
          --   from one or more of the provided modules.
        , storeSupers   :: IORef (Map ModuleName (Map E.Name Super)) 

          -- | Fully loaded interface files.
          --   In future we want to load parts of interface files on demand, 
          --   and not the whole lot.q
        , storeInterfaces :: IORef [InterfaceAA] }


---------------------------------------------------------------------------------------------------
-- | Metadata for interfaces currently loaded into the store.
data Meta
        = Meta
        { metaFilePath     :: FilePath
        , metaTimeStamp    :: UTCTime
        , metaModuleName   :: ModuleName }


-- | Interface for some top-level super.
data Super
        = Super
        { -- | Name of the super.
          superName             :: E.Name

          -- | Where the super was imported from.
          --
          --   This is the module that the name was resolved from. If that
          --   module re-exported an imported name then this may not be the
          --   module the super was actually defined in.
        , superModuleName       :: ModuleName

          -- | Tetra type for the super.
        , superTetraType        :: Type E.Name

          -- | Salt type for the super.
        , superSaltType         :: Type A.Name 

          -- | Import source for the super.
          --
          --   This can be used to refer to the super from a client module.
        , superImportValue      :: ImportValue E.Name }


---------------------------------------------------------------------------------------------------
-- | An empty interface store.
new :: IO Store
new
 = do   refMeta         <- newIORef []
        refSupers       <- newIORef Map.empty
        refInterfaces   <- newIORef []
        return  $ Store 
                { storeMeta             = refMeta
                , storeSupers           = refSupers 
                , storeInterfaces       = refInterfaces }


-- | Add a pre-loaded interface file to the store.
wrap    :: Store -> InterfaceAA -> IO ()
wrap store int
 = do   modifyIORef (storeMeta store)
         $ \meta   -> meta ++ [metaOfInterface int] 

        modifyIORef (storeSupers store)
         $ \supers -> Map.insert (interfaceModuleName int)
                                 (supersOfInterface   int)
                                 supers

        modifyIORef (storeInterfaces store)
         $ \ints   -> ints ++ [int]


-- | Load a new interface into the store.
load    :: Store -> FilePath -> IO (Maybe Error)
load store filePath
 = do   timeStamp  <- getModificationTime filePath
        str        <- readFile filePath

        case loadInterface filePath timeStamp str of
         Left err  
          ->    return $ Just err

         Right int 
          -> do wrap store int
                return Nothing


-- | Get metadata of interfaces currently in the store.
getMeta :: Store -> IO [Meta]
getMeta store
 = do   mm      <- readIORef (storeMeta store)
        return  $ mm


-- | Get names of the modules currently in the store.
getModuleNames :: Store -> IO [ModuleName]
getModuleNames store
 = do   supers  <- readIORef (storeSupers store)
        return  $ Map.keys supers


-- | Get the fully loaded interfaces.
getInterfaces :: Store -> IO [InterfaceAA]
getInterfaces store
 = do   ints    <- readIORef (storeInterfaces store)
        return ints


-- | See if a super is defined in any of the given modules, and if so
--   return the module name and super type.
--
--   NOTE: This function returns an IO [Super] in preparation for the case
--   where we load data from interface files on demand. We want to ensure
--   that the caller is also in IO, to make the refactoring easier later.
--
findSuper
        :: Store
        -> E.Name               -- ^ Name of desired super.
        -> [ModuleName]         -- ^ Names of modules to search.
        -> IO [Super]

findSuper store n modNames 
 = do   supers  <- readIORef (storeSupers store)
        return $ mapMaybe
                (\modName -> do
                        nSupers <- Map.lookup modName supers
                        Map.lookup n nSupers)
                modNames


---------------------------------------------------------------------------------------------------
-- | Extract metadata from an interface.
metaOfInterface   :: InterfaceAA -> Meta
metaOfInterface int
        = Meta
        { metaFilePath   = interfaceFilePath   int
        , metaTimeStamp  = interfaceTimeStamp  int
        , metaModuleName = interfaceModuleName int }


-- | Extract a map of super interfaces from the given module interface.
--
--   This contains all the information needed to import a super into
--   a client module.
--
supersOfInterface :: InterfaceAA -> Map E.Name Super
supersOfInterface int
 | Just mmTetra <- interfaceTetraModule int
 , Just mmSalt  <- interfaceSaltModule  int
 = let  
        -- The current module name.
        modName = interfaceModuleName int

        -- Collect Tetra types for all supers exported by the module.
        ntsTetra    
         = Map.fromList
           [ (n, t)     | (n, esrc)     <- moduleExportValues mmTetra
                        , let Just t    =  takeTypeOfExportSource esrc ]

        -- Collect Salt  types of all supers exported by the module.
        ntsSalt 
         = Map.fromList
           [ (n, t)     | (n, esrc)     <- moduleExportValues mmSalt
                        , let Just t    =  takeTypeOfExportSource esrc ]

        -- Build call patterns for all locally defined supers.
        --  The call pattern is the number of type parameters then value parameters
        --  for the super. We assume all supers are in prenex form, so they take
        --  all their type arguments before their value arguments.
        makeLocalArity b x
         | BName nSuper _       <- b
         , cs                   <- takeCallConsFromExp x
         , Just (csType, csValue, csBox) <- splitStdCallCons cs
         = (nSuper, (length csType, length csValue, length csBox))

         | otherwise            = error "supersOfInterface: not prenex"

        nsLocalArities :: Map E.Name (Int, Int, Int)
                =  Map.fromList
                $  mapTopBinds makeLocalArity
                $  mmTetra

        -- Build an ImportSource for the given super name. A client module
        -- can use this to import the super into itself.
        makeImportValue n

         -- Super was defined as a top-level binding in the current module.
         | Just (aType, aValue, nBoxes) <- Map.lookup n nsLocalArities
         , Just tTetra                  <- Map.lookup n ntsTetra
         = ImportValueModule modName n tTetra (Just (aType, aValue, nBoxes))

         -- Super was imported into the current module from somewhere else.
         -- Pass along the same import declaration to the client.
         | Just impt            <- lookup n (moduleImportValues mmTetra)
         = impt

         | otherwise            = error $ "supersOfInterface: no source" ++ (show n)

        makeSuper n tTetra
         | E.NameVar s  <- n
         = Just $ Super
                { superName         = n
                , superModuleName   = moduleName mmTetra
                , superTetraType    = tTetra
                , superSaltType     = let Just t = Map.lookup (A.NameVar s) ntsSalt  in t 
                , superImportValue  = makeImportValue n }
         | otherwise    = Nothing


   in   Map.fromList   
          [ (n, super)  | (n, tTetra)    <- Map.toList ntsTetra 
                        , let Just super = makeSuper n tTetra ]

 | otherwise
 = Map.empty

