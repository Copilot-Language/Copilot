--------------------------------------------------------------------------------

{-# LANGUAGE RankNTypes, NamedFieldPuns, ScopedTypeVariables, GADTs,
             LambdaCase #-}

module Copilot.Kind.IL.Translate ( translate ) where

import Copilot.Kind.IL.Spec
import Copilot.Kind.Misc.Cast
import Copilot.Kind.CoreUtils.Operators

import qualified Copilot.Core as C

import qualified Data.Map.Strict as Map

import Control.Applicative ((<$>))
import Control.Monad.State

import Data.Char
import Data.List (foldl')

import Text.Printf

--------------------------------------------------------------------------------

-- 'nc' stands for **naming conventions**
ncSeq :: C.Id -> SeqId
ncSeq = printf "s%d"

-- We assume all local variables have distinct names whatever their scopes are
ncLocal :: C.Name -> SeqId
ncLocal s = "l" ++ dropWhile (not . isNumber) s

ncExternVar :: C.Name -> SeqId
ncExternVar n = "ext_" ++ n

ncExternFun :: C.Name -> SeqId
ncExternFun n = "_" ++ n

ncUnhandledOp :: String -> String
ncUnhandledOp = id

--------------------------------------------------------------------------------

-- | Translates a Copilot specification to an IL specification

translate :: C.Spec -> IL
translate spec = il { bounds = bounds }
  where (bounds, spec') = addBounds spec
        il = translate' spec'
        translate' (C.Spec {C.specStreams, C.specProperties}) = runTrans $ do

          let modelInit = concatMap streamInit specStreams

          mainConstraints <- mapM streamRec specStreams
          properties <- Map.fromList <$>
            forM specProperties
              (\(C.Property {C.propertyName, C.propertyExpr}) -> do
                e' <- expr Bool propertyExpr
                return (propertyName, e'))

          localConstraints <- getLocalVarsConstraints

          return IL
            { modelInit
            , modelRec = mainConstraints ++ localConstraints
            , properties
            , bounds = []
            }

addBounds :: C.Spec -> ([PropId], C.Spec)
addBounds spec@(C.Spec { C.specStreams, C.specProperties }) =
  (map propName properties, spec {C.specProperties = specProperties ++ properties})
  where
    properties :: [C.Property]
    properties = foldl' (++) [] $ map bound specStreams
    bound :: C.Stream -> [C.Property]
    bound (C.Stream { C.streamId, C.streamExprType }) = case streamExprType of
      C.Int8    -> bound' streamId C.Int8
      C.Int16   -> bound' streamId C.Int16
      C.Int32   -> bound' streamId C.Int32
      C.Int64   -> bound' streamId C.Int64
      C.Word8   -> bound' streamId C.Word8
      C.Word16  -> bound' streamId C.Word16
      C.Word32  -> bound' streamId C.Word32
      C.Word64  -> bound' streamId C.Word64
      _         -> []
    bound' :: (Ord a, Bounded a) => C.Id -> C.Type a ->  [C.Property]
    bound' streamId t = [C.Property (ncSeq streamId ++ "_bounds")
      $ C.Op2 C.And
      (C.Op2 (C.Le t) (C.Const t minBound) (C.Drop t 0 streamId))
      (C.Op2 (C.Ge t) (C.Const t maxBound) (C.Drop t 0 streamId))]
    propName (C.Property name _) = name

streamInit :: C.Stream -> [Constraint]
streamInit (C.Stream { C.streamId       = id
                     , C.streamBuffer   = b :: [val]
                     , C.streamExprType = ty}) =

  zipWith initConstraint [0..] b
  where
    initConstraint :: Integer -> val -> Constraint
    initConstraint p v = casting ty $ \ty' ->
      Op2 Bool Eq
        (SVal ty' (ncSeq id) (Fixed p))
        (Const ty' $ cast ty' $ toDyn ty v)

streamRec :: C.Stream -> Trans Constraint
streamRec (C.Stream { C.streamId       = id
                    , C.streamExpr     = e
                    , C.streamBuffer   = b
                    , C.streamExprType = ty})
  = casting ty $ \ty' -> do
      e' <- expr ty' e
      return $ Op2 Bool Eq (SVal ty' (ncSeq id) (_n_plus $ length b)) e'

--------------------------------------------------------------------------------

addSign :: (Ord t, Num t) => Type t' -> C.Type t -> t -> Trans (Expr t')
addSign t ct v
  | v >= 0    = return $ Const t (cast t $ toDyn ct v)
  | otherwise = return $ Op1 t Neg (Const t (cast t $ toDyn ct (-v)))

expr :: Type t -> C.Expr a -> Trans (Expr t)

expr t (C.Const ct@C.Double v) = addSign t ct v
expr t (C.Const ct@C.Float v)  = addSign t ct v
expr t (C.Const ct@C.Int8 v)   = addSign t ct v
expr t (C.Const ct@C.Int16 v)  = addSign t ct v
expr t (C.Const ct@C.Int32 v)  = addSign t ct v
expr t (C.Const ct@C.Int64 v)  = addSign t ct v
expr t (C.Const ct v)          = return $ Const t (cast t $ toDyn ct v)

expr t (C.Label _ _ e) = expr t e

expr t (C.Drop _ k id) = return $ SVal t (ncSeq id) (_n_plus k)

expr t (C.Local ta _ name ea eb) = casting ta $ \ta' -> do
  ea' <- expr ta' ea
  newLocalVar
    (Op2 Bool Eq (SVal ta' (ncLocal name) _n_) ea')
  expr t eb

expr t (C.Var _ name) = return $ SVal t (ncLocal name) _n_

expr t (C.ExternVar _ name _) = return $ SVal t (ncExternVar name) _n_

expr t (C.ExternFun _ name args _ _) = do
  args' <- mapM trArg args
  return $ FunApp t (ncExternFun name) args'
  where
    trArg (C.UExpr {C.uExprExpr, C.uExprType}) = casting uExprType $ \ta ->
      U <$> expr ta uExprExpr

-- Arrays and functions are treated the same way
expr t (C.ExternArray _ tb name _ ind _ _) = casting tb $ \_ -> do
  ind' <- U <$> expr Integer ind
  return $ FunApp t (ncExternFun name) [ind']

expr t (C.Op1 op e) = handleOp1 t (op, e) expr notHandled Op1
  where notHandled (UnhandledOp1 opName ta _) = do
          e' <- U <$> expr ta e
          return $ FunApp t (ncUnhandledOp opName) [e']

expr t (C.Op2 op e1 e2) = handleOp2 t (op, e1, e2) expr notHandled Op2 (Op1 Bool Not)
  where notHandled (UnhandledOp2 opName ta tb _) = do
          e1' <- U <$> expr ta e1
          e2' <- U <$> expr tb e2
          return $ FunApp t (ncUnhandledOp opName) [e1', e2']

expr t (C.Op3 (C.Mux _) cond e1 e2) = do
  cond' <- expr Bool cond
  e1'   <- expr t    e1
  e2'   <- expr t    e2
  return $ Ite t cond' e1' e2'

--------------------------------------------------------------------------------

mkVarName :: String -> [U Expr] -> String
mkVarName name args = name ++ "_" ++ concatMap argToString args

argToString :: U Expr -> String
argToString (U (Const Integer x)) = show x
argToString (U (Op2 _ Add e1 e2)) = argToString (U e1) ++ argToString (U e2)
argToString (U _) = error "translating arg to string (should never happen)"

data TransST = TransST
  { _localVarsConstraints :: [Constraint] }

type Trans = State TransST

newLocalVar :: Constraint -> Trans ()
newLocalVar c =
  modify $ \st -> st {_localVarsConstraints = c : _localVarsConstraints st}

getLocalVarsConstraints :: Trans [Constraint]
getLocalVarsConstraints = _localVarsConstraints <$> get

runTrans :: Trans a -> a
runTrans m = evalState m $ TransST []

--------------------------------------------------------------------------------
