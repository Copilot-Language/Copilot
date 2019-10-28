--------------------------------------------------------------------------------
-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
--------------------------------------------------------------------------------

{-# LANGUAGE RebindableSyntax #-}

module EngineExample ( engineExample ) where

import Language.Copilot
import qualified Prelude as P
--import qualified Copilot.Compile.SBV as S

{- 
  "If the majority of the engine temperature probes exeeds 250 degrees, then the
  cooler is engaged and remains engaged until the majority of the engine
  temperature probes drop to 250 or below.  Otherwise, trigger an immediate
  shutdown of the engine."  -}

engineMonitor :: Spec
engineMonitor = do
  trigger "shutoff" (not ok) [arg maj]

  where
  vals     = [ externW8 "tmp_probe_0" two51
             , externW8 "tmp_probe_1" two51
             , externW8 "tmp_probe_2" zero]
  exceed   = map (> 250) vals
  maj      = majority exceed
  checkMaj = aMajority exceed maj
  ok       = alwaysBeen ((maj && checkMaj) ==> extern "cooler" cooler) 

  two51  = Just $ [251, 251] P.++ repeat (250 :: Word8)
  zero   = Just $ repeat (0 :: Word8)
  cooler = Just $ [True, True] P.++ repeat False

engineExample :: IO ()
engineExample = interpret 10 engineMonitor

main = engineExample

--  reify engineMonitor >>= S.compile (S.Params { S.prefix = Just "engine" })
  

