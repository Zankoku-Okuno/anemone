{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}

module Language.Bslisp.TreeWalk.Environment
  ( Env(..)
  , Binding(..)
  , lookup
  , define
  , valueNamespace
  , newEmptyEnv
  , newDefaultEnv
  , newChild
  ) where

import Prelude hiding (lookup)

import Control.Monad (forM_)
import Control.Monad.IO.Class (MonadIO,liftIO)
import Data.IORef (newIORef,readIORef,modifyIORef')
import Data.Symbol.Unsafe (Symbol(..),intern)
import Language.Bslisp.TreeWalk.Unsafe.Types (Env(..),Namespace(..),Binding(..))
import Language.Bslisp.TreeWalk.Value (PrimUnary(..),PrimBin(..))
import Language.Bslisp.TreeWalk.Value (PrimCaseBin(..),PrimCaseQuat(..))
import Language.Bslisp.TreeWalk.Value (Value(..),PrimOp(..),PrimAp(..))

import qualified Data.IntMap.Strict as Map


newEnv :: (MonadIO io) => Maybe Env -> io Env
newEnv parent = do
  nsMap <- liftIO $ newIORef Map.empty
  pure Env{parent,namespaces=nsMap,name=Nothing,createdAt=Nothing}

newEmptyEnv :: (MonadIO io) =>  io Env
newEmptyEnv = newEnv Nothing

newChild :: (MonadIO io) => Env -> io Env
newChild = newEnv . Just

newDefaultEnv :: (MonadIO io) =>  io Env
newDefaultEnv = do
  env <- newEmptyEnv
  forM_ primInfo $ \(x, prim) ->
    unsafeDefine env valueNamespace (intern x) prim
  return env
  where
  primInfo =
    -- core features
    [ ("__lambda__", PrimOp PrimLambda)
    , ("__eval__", PrimAp PrimEval)
    , ("__force__", PrimAp PrimForce)
    -- sequential programming
    , ("__sequence__", PrimOp PrimSequence)
    , ("__define-in__", PrimAp PrimDefineIn)
    , ("__define__", PrimOp PrimDefine)
    -- arithmetic
    , ("__add__", PrimAp $ PrimBin PrimAdd)
    -- lists
    , ("__list__", PrimOp PrimList)
    , ("__cons__", PrimAp $ PrimBin PrimCons)
    , ("__uncons__", PrimAp $ PrimCaseBin PrimUncons)
    -- sexprs
    , ("__sexpr-intro__", PrimAp $ PrimUnary PrimSexprIntro)
    , ("__sexpr-elim__", PrimAp $ PrimCaseQuat PrimSexprElim)
    , ("__sym-intro__", PrimAp $ PrimUnary PrimSymIntro)
    , ("__sym-elim__", PrimAp $ PrimUnary PrimSymElim)
    -- metadata
    , ("__upd-name__", PrimAp $ PrimBin PrimUpdName)
    , ("__upd-loc__", PrimAp $ PrimBin PrimUpdLoc)
    ]

valueNamespace :: Symbol
valueNamespace = intern "value"

lookup :: (MonadIO io) => Env -> Symbol -> Symbol -> io (Maybe Binding)
lookup env0 (Symbol nsId _) (Symbol xId _) = liftIO $ go env0
  where
  go env = Map.lookup nsId <$> readIORef (namespaces env) >>= \case
    Just ns -> do
      Map.lookup xId <$> readIORef (bindings ns) >>= \case
        Just bound -> pure (Just bound)
        Nothing -> goParent env
    Nothing -> goParent env
  goParent env = case parent env of
    Nothing -> pure Nothing
    Just p -> go p

define :: (MonadIO io) => Env -> Symbol -> Symbol -> Value -> io ()
define env ns x v = lookup env ns x >>= \case
  Nothing -> unsafeDefine env ns x v
  Just _ -> error $ "unimplemented: redefinition error " ++ show x

unsafeDefine :: (MonadIO io) => Env -> Symbol -> Symbol -> Value -> io ()
unsafeDefine env ns@(Symbol nsId _) x@(Symbol xId _) v = liftIO $ do
  Map.lookup nsId <$> readIORef (namespaces env) >>= \case
    Just namespace -> bind namespace
    Nothing -> do
      bindings <- newIORef Map.empty
      let namespace = Ns{name=ns,bindings}
      modifyIORef' (namespaces env) $ Map.insert nsId namespace
      bind namespace
  where
  bind namespace = modifyIORef' (bindings namespace) $
    Map.insert xId Bound{name=x,value=v}
