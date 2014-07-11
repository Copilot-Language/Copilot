--------------------------------------------------------------------------------
-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
--------------------------------------------------------------------------------

module Main (main) where

import qualified Copilot.Core as Core
import Copilot.Language.Reify
import Copilot.Core.Interpret
import Copilot.Core.PrettyPrint

import qualified Copilot.Kind.TransSys    as TS
import qualified Copilot.Kind.Kind2       as K2
import Copilot.Kind.Kind2.Prover          as P
import Copilot.Kind.Naive

import Grey

--------------------------------------------------------------------------------

line = replicate 40 '-'

main :: IO ()
main =  do
  cspec <- reify spec
  prove (naiveProver def) scheme cspec
  --putStrLn $ K2.prettyPrint . K2.toKind2 K2.Modular . TS.translate $ cspec
  return ()

--------------------------------------------------------------------------------
