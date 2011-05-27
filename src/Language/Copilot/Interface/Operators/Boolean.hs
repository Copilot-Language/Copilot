-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
-- CoPilot is licensed under a Creative Commons Attribution 3.0 Unported License.
-- See http://creativecommons.org/licenses/by/3.0 for license terms.

-- |

{-# LANGUAGE UnicodeSyntax #-}

module Language.Copilot.Interface.Operators.Boolean
  ( Boolean (..)
  ) where

import qualified Prelude as P
import Language.Copilot.Interface.Prelude

class Boolean α where
  (&&)     ∷ α → α → α
  (||)     ∷ α → α → α
  not      ∷ α → α
  true     ∷ α
  false    ∷ α
  fromBool ∷ Bool → α

instance Boolean Bool where
  (&&)      = (P.&&)
  (||)      = (P.||)
  not       = P.not
  true      = P.True
  false     = P.False
  fromBool  = P.id
