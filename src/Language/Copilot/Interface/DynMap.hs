-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
-- CoPilot is licensed under a Creative Commons Attribution 3.0 Unported License.
-- See http://creativecommons.org/licenses/by/3.0 for license terms.

-- |

{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UnicodeSyntax #-}

module Language.Copilot.Interface.DynMap
  ( DynMap
  , DynKey (..)
  , empty
  , insert
  ) where

import Data.IntMap (IntMap)
import qualified Data.IntMap as M
import Data.Type.Equality
import Language.Copilot.Core (HasType (..))
import Language.Copilot.Core.HeteroMap (HeteroMap (..), Key, Key2Int (..))

data Dyn f = ∀ α . HasType α ⇒ Dyn (f α)

--data Dyn ∷ (* → *) → * where
--  Dyn
--    ∷ HasType α
--    ⇒ f α
--    → Dyn f

--unDyn
--  ∷ Dyn f
--  → (forall α . HasType α ⇒ f α)
--unDyn (Dyn x) = x

newtype DynMap f = DynMap (IntMap (Dyn f))

newtype DynKey α = DynKey Int
  deriving (Eq, Ord, Show)

instance HeteroMap DynMap where
  type Key DynMap = DynKey

  lookup (DynKey k) (DynMap m) = x
    where
      Just x = M.lookup k m >>= fromDyn

  mapWithKey f (DynMap m) = DynMap $
    M.mapWithKey (\ k x → mapDyn (f (DynKey k)) x) m

  fold f b0 (DynMap m) = M.fold
    (\ dyn b -> accDyn f dyn b) b0 m

  foldWithKey f b0 (DynMap m) = M.foldWithKey
    (\ k x b → accDyn (f (DynKey k)) x b) b0 m

  foldMapWithKey = undefined

  foldMapWithKeyM = undefined

  traverseWithKey _ _ = undefined

instance Key2Int DynKey where
  key2Int (DynKey n) = n

empty ∷ DynMap f
empty = DynMap M.empty

insert
  ∷ HasType α
  ⇒ Int
  → f α
  → DynMap f
  → DynMap f
insert k x (DynMap m) = DynMap $ M.insert k (toDyn x) m

toDyn
  ∷ HasType α
  ⇒ f α
  → Dyn f
toDyn = Dyn

fromDyn
  ∷ HasType α
  ⇒ Dyn f
  → Maybe (f α)
fromDyn (Dyn x) =
  -- Proof at runtime that type 'a' is equal to type 'b'
  eqT typeOf typeOf >>= \ w → Just (coerce (cong w) x)

mapDyn
  ∷ (forall α . f α → g α)
  → Dyn f
  → Dyn g
mapDyn f (Dyn x) = Dyn (f x)

accDyn
  ∷ (∀ α . f α → β → β)
  → (Dyn f → β → β)
accDyn f (Dyn x) b = f x b
