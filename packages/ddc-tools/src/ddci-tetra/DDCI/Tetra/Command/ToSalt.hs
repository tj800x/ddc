module DDCI.Tetra.Command.ToSalt
        (cmdToSalt)
where
import DDCI.Tetra.State
import DDC.Interface.Source
import DDC.Driver.Stage
import DDC.Build.Pipeline   
import DDC.Base.Pretty
import qualified DDC.Driver.Config      as D


-- Convert Disciple Core Tetra to Disciple Core Salt.
cmdToSalt :: State -> D.Config -> Source -> String -> IO ()
cmdToSalt _state config source str
 = let  
        pmode   = D.prettyModeOfConfig $ D.configPretty config

        pipeLoad
         = pipeText (nameOfSource source)
                    (lineStartOfSource source)
                    str
         $ stageSourceTetraLoad config source
         [ PipeCoreReannotate (const ())
         [ stageTetraToSalt     config source 
         [ PipeCoreOutput pmode SinkStdout ]]]

   in do
        errs    <- pipeLoad
        case errs of
         []     -> return ()
         es     -> putStrLn (renderIndent $ ppr es)
