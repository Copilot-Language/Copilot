{-# LANGUAGE GADTs #-}

module Copilot.Compile.C.Translate where

import Control.Monad.State

import Copilot.Core
import Copilot.Compile.C.Util

import qualified Language.C99.Simple as C

-- | Translates a Copilot expression into a C99 expression.
transexpr :: Expr a -> State FunEnv C.Expr
transexpr (Const ty x) = return $ constty ty x

transexpr (Local ty1 _ name e1 e2) = do
  e1' <- transexpr e1
  e2' <- transexpr e2
  statetell ([C.Decln Nothing (transtype ty1) name (C.InitExpr e1')], [])
  return $ e2'

transexpr (Var _ n) = return $ C.Ident n

transexpr (Drop _ amount sid) = do
  let var    = streamname sid
      indexvar = indexname sid
      index  = case amount of
        0 -> C.Ident indexvar
        n -> C.Ident indexvar C..+ C.LitInt (fromIntegral n)
  return $ C.Index (C.Ident var) index

transexpr (ExternVar _ name _) = return $ C.Ident (excpyname name)

transexpr (ExternFun _ _ _ _ _) = undefined

transexpr (Label _ _ _) = undefined

transexpr (Op1 op e) = do
  e' <- transexpr e
  return $ transop1 op e'

transexpr (Op2 op e1 e2) = do
  e1' <- transexpr e1
  e2' <- transexpr e2
  return $ transop2 op e1' e2'

transexpr (Op3 op e1 e2 e3) = do
  e1' <- transexpr e1
  e2' <- transexpr e2
  e3' <- transexpr e3
  return $ transop3 op e1' e2' e3'


-- | Translates a Copilot unary operator and arguments into a C99 expression.
transop1 :: Op1 a b -> C.Expr -> C.Expr
transop1 op e = case op of
  Not             -> (C..!) e
  Abs      _      -> funcall "abs"      [e]
  Sign     _      -> funcall "copysign" [C.LitDouble 1.0, e]
  Recip    _      -> C.LitDouble 1.0 C../ e
  Exp      _      -> funcall "exp"   [e]
  Sqrt     _      -> funcall "sqrt"  [e]
  Log      _      -> funcall "log"   [e]
  Sin      _      -> funcall "sin"   [e]
  Tan      _      -> funcall "tan"   [e]
  Cos      _      -> funcall "cos"   [e]
  Asin     _      -> funcall "asin"  [e]
  Atan     _      -> funcall "atan"  [e]
  Acos     _      -> funcall "acos"  [e]
  Sinh     _      -> funcall "sinh"  [e]
  Tanh     _      -> funcall "tanh"  [e]
  Cosh     _      -> funcall "cosh"  [e]
  Asinh    _      -> funcall "asinh" [e]
  Atanh    _      -> funcall "atanh" [e]
  Acosh    _      -> funcall "acosh" [e]
  BwNot    _      -> (C..~) e
  Cast     ty _   -> C.Cast (transtypename ty) e
  GetField _  _ n -> C.Dot e n

-- | Translates a Copilot binary operator and arguments into a C99 expression.
transop2 :: Op2 a b c -> C.Expr -> C.Expr -> C.Expr
transop2 op e1 e2 = case op of
  And          -> e1 C..&& e2
  Or           -> e1 C..|| e2
  Add      _   -> e1 C..+  e2
  Sub      _   -> e1 C..-  e2
  Mul      _   -> e1 C..*  e2
  Mod      _   -> e1 C..%  e2
  Div      _   -> e1 C../  e2
  Fdiv     _   -> e1 C../  e2
  Pow      _   -> funcall "pow" [e1, e2]
  Logb     _   -> funcall "log" [e2] C../ funcall "log" [e1]
  Eq       _   -> e1 C..== e2
  Ne       _   -> e1 C..!= e2
  Le       _   -> e1 C..<= e2
  Ge       _   -> e1 C..>= e2
  Lt       _   -> e1 C..<  e2
  Gt       _   -> e1 C..>  e2
  BwAnd    _   -> e1 C..&  e2
  BwOr     _   -> e1 C..|  e2
  BwXor    _   -> e1 C..^  e2
  BwShiftL _ _ -> e1 C..<< e2
  BwShiftR _ _ -> e1 C..>> e2
  Index    _   -> C.Index e1 e2

-- | Translates a Copilot ternaty operator and arguments into a C99 expression.
transop3 :: Op3 a b c d -> C.Expr -> C.Expr -> C.Expr -> C.Expr
transop3 op e1 e2 e3 = case op of
  Mux _ -> C.Cond e1 e2 e3

-- | Give a C99 literal expression based on a value and a type.
constty :: Type a -> a -> C.Expr
constty ty = case ty of
  Bool   -> C.LitBool
  Int8   -> C.LitInt . fromIntegral
  Int16  -> C.LitInt . fromIntegral
  Int32  -> C.LitInt . fromIntegral
  Int64  -> C.LitInt . fromIntegral
  Word8  -> C.LitInt . fromIntegral
  Word16 -> C.LitInt . fromIntegral
  Word32 -> C.LitInt . fromIntegral
  Word64 -> C.LitInt . fromIntegral
  Float  -> C.LitFloat
  Double -> C.LitDouble

-- | Translate a Copilot type to a C99 type.
transtype :: Type a -> C.Type
transtype ty = case ty of
  Bool      -> C.TypeSpec $ C.TypedefName "bool"
  Int8      -> C.TypeSpec $ C.TypedefName "int8_t"
  Int16     -> C.TypeSpec $ C.TypedefName "int16_t"
  Int32     -> C.TypeSpec $ C.TypedefName "int32_t"
  Int64     -> C.TypeSpec $ C.TypedefName "int64_t"
  Word8     -> C.TypeSpec $ C.TypedefName "uint8_t"
  Word16    -> C.TypeSpec $ C.TypedefName "uint16_t"
  Word32    -> C.TypeSpec $ C.TypedefName "uint32_t"
  Word64    -> C.TypeSpec $ C.TypedefName "uint64_t"
  Float     -> C.TypeSpec C.Float
  Double    -> C.TypeSpec C.Double
  Array ty' -> C.Array (transtype ty') Nothing
  Struct s  -> C.TypeSpec $ C.Struct (typename s)

-- | Translate a Copilot type intro a C typename
transtypename :: Type a -> C.TypeName
transtypename ty = C.TypeName $ transtype ty

-- | Translate a Copilot Spec to a header and a C transunit.
transspec :: Spec -> (C.TransUnit, C.TransUnit)
transspec spec = (hfile, cfile) where
  streams  = specStreams spec

  cfile = C.TransUnit (concat gendeclns) genfuncs where
    (gendeclns, genfuncs) = unzip $ map transstream streams

  hfile = undefined


-- | Translate a stream into a generator function and global variables
transstream :: Stream -> ([C.Decln], C.FunDef)
transstream (Stream sid buff expr ty) = (declns, genfunc) where
  (cexpr, (cvars, _)) = runState (transexpr expr) mempty

  cty     = transtype ty
  name    = generatorname sid
  genfunc = C.FunDef cty name [] cvars [C.Return $ Just cexpr]

  declns   = [ mkbuffdecln  sid ty buff
             , mkindexdecln sid
             , mkvaldecln   sid ty buff
             ]

-- | Make a C buffer variable and initialise it with the stream buffer.
mkbuffdecln :: Id -> Type a -> [a] -> C.Decln
mkbuffdecln sid ty xs = C.Decln (Just C.Static) cty name initvals where
  name     = buffername sid
  cty      = C.Array (transtype ty) (Just $ C.LitInt $ fromIntegral buffsize)
  buffsize = length xs
  initvals = mkinits ty xs

-- | Make a C index variable and initialise it to 0.
mkindexdecln :: Id -> C.Decln
mkindexdecln sid = C.Decln (Just C.Static) cty name initval where
  name    = indexname sid
  cty     = C.TypeSpec $ C.TypedefName "size_t"
  initval = C.InitExpr $ C.LitInt 0

-- | Make C stream declaration and initialise it with the first value of the
-- | buffer of the same stream.
mkvaldecln :: Id -> Type a -> [a] -> C.Decln
mkvaldecln sid ty buff = C.Decln (Just C.Static) cty name initval where
  name    = streamname sid
  cty     = transtype ty
  initval = mkinit ty (head buff)

-- | Make an initial declaration from a list of values.
mkinits :: Type a -> [a] -> C.Init
mkinits ty xs = C.InitArray $ map (mkinit ty) xs

-- | Make an initial declaration from a single value.
mkinit :: Type a -> a -> C.Init
mkinit (Array ty') xs = C.InitArray $ map (mkinit ty') (arrayelems xs)
mkinit ty          x  = C.InitExpr  $ constty ty x
