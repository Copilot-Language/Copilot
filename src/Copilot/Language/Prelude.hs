--------------------------------------------------------------------------------
-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
--------------------------------------------------------------------------------

-- | Reexports 'Prelude' from package "base"
-- hiding identifiers redefined by Copilot.

module Copilot.Language.Prelude
  ( module Prelude
  ) where

import Prelude hiding
  ( (++)
  , Eq (..)
  , Integral (..)
  , Ord (..)
  , (&&)
  , (||)
  , const
  , drop
  , not
  , mod )

--------------------------------------------------------------------------------