{-# LANGUAGE TypeOperators, TupleSections, FlexibleInstances #-}

-- |
-- Module: Language.KURE.Combinators
-- Copyright: (c) 2012 The University of Kansas
-- License: BSD3
--
-- Maintainer: Neil Sculthorpe <neil@ittc.ku.edu>
-- Stability: beta
-- Portability: ghc
--
-- This module provides various monadic and arrow combinators that are particularly useful when
-- working with translations.

module Language.KURE.Combinators
           ( -- * Monad Combinators
             -- ** Monads with a Catch
             MonadCatch(..)
           , (<<+)
           , catchesM
           , tryM
           , mtryM
           , attemptM
           , testM
           , notM
           , modFailMsg
           , setFailMsg
           , prefixFailMsg
           , withPatFailMsg
             -- ** Conditionals
           , guardMsg
           , guardM
           , ifM
           , whenM
           , unlessM
             -- * Arrow Combinators
             -- ** Categories with a Catch
           , CategoryCatch(..)
           , (<+)
           , readerT
           , acceptR
           , accepterR
           , tryR
           , attemptR
           , changedR
           , repeatR
           , (>+>)
           , orR
           , andR
           , catchesT
             -- ** Basic Routing
             -- | The names 'result' and 'argument' are taken from Conal Elliott's semantic editor combinators.
           , result
           , argument
           , toFst
           , toSnd
           , swap
           , fork
           , forkFirst
           , forkSecond
           , constant
) where

import Prelude hiding (id , (.), catch)

import Control.Monad
import Control.Category
import Control.Arrow

import Data.Monoid
import Data.List (isPrefixOf)

infixl 3 >+>, <+, <<+

------------------------------------------------------------------------------------------

-- | 'Monad's with a catch for 'fail'.
--   The following law is expected to hold:
--
-- > fail msg `catchM` f == f msg

class Monad m => MonadCatch m where
  -- | Catch a failing monadic computation.
  catchM :: m a -> (String -> m a) -> m a

------------------------------------------------------------------------------------------

-- | A monadic catch that ignores the error message.
(<<+) :: MonadCatch m => m a -> m a -> m a
ma <<+ mb = ma `catchM` const mb

-- | Select the first monadic computation that succeeds, discarding any thereafter.
catchesM :: MonadCatch m => [m a] -> m a
catchesM = foldr (<<+) (fail "catchesM failed")

-- | Catch a failing monadic computation, making it succeed with a constant value.
tryM :: MonadCatch m => a -> m a -> m a
tryM a ma = ma <<+ return a

-- | Catch a failing monadic computation, making it succeed with 'mempty'.
mtryM :: (MonadCatch m, Monoid a) => m a -> m a
mtryM = tryM mempty

-- | Catch a failing monadic computation, making it succeed with an error message.
attemptM :: MonadCatch m => m a -> m (Either String a)
attemptM ma = liftM Right ma `catchM` (return . Left)

-- | Determine if a monadic computation succeeds.
testM :: MonadCatch m => m a -> m Bool
testM ma = liftM (const True) ma <<+ return False

-- | Fail if the 'Monad' succeeds; succeed with @()@ if it fails.
notM :: MonadCatch m => m a -> m ()
notM ma = ifM (testM ma) (fail "notM of success") (return ())

-- | Modify the error message of a failing monadic computation.
--   Successful computations are unaffected.
modFailMsg :: MonadCatch m => (String -> String) -> m a -> m a
modFailMsg f ma = ma `catchM` (fail . f)

-- | Set the error message of a failing monadic computation.
--   Successful computations are unaffected.
setFailMsg :: MonadCatch m => String -> m a -> m a
setFailMsg msg = modFailMsg (const msg)

-- | Add a prefix to the error message of a failing monadic computation.
--   Successful computations are unaffected.
prefixFailMsg :: MonadCatch m => String -> m a -> m a
prefixFailMsg msg = modFailMsg (msg ++)

-- | Use the given error message whenever a monadic pattern match failure occurs.
withPatFailMsg :: MonadCatch m => String -> m a -> m a
withPatFailMsg msg = modFailMsg (\ e -> if "Pattern match failure" `isPrefixOf` e then msg else e)

------------------------------------------------------------------------------------------

-- | Similar to 'guard', but invokes 'fail' rather than 'mzero'.
guardMsg ::  Monad m => Bool -> String -> m ()
guardMsg b msg = unless b (fail msg)

-- | As 'guardMsg', but with a default error message.
guardM ::  Monad m => Bool -> m ()
guardM b = guardMsg b "guardM failed"

-- | if-then-else lifted over a monadic predicate.
ifM ::  Monad m => m Bool -> m a -> m a -> m a
ifM mb m1 m2 = do b <- mb
                  if b then m1 else m2

-- | if the monadic predicate holds then perform the monadic action, else fail.
whenM ::  Monad m => m Bool -> m a -> m a
whenM mb ma = ifM mb ma (fail "whenM: condition False")

-- | if the monadic predicate holds then fail, else perform the monadic action.
unlessM ::  Monad m => m Bool -> m a -> m a
unlessM mb ma = ifM mb (fail "unlessM: condition True") ma

------------------------------------------------------------------------------------------

-- | 'Category's with failure and catching.
--   The following law is expected to hold:
--
-- > failT msg `catchT` f == f msg

class Category (~>) => CategoryCatch (~>) where
  -- | The failing 'Category'.
  failT :: String -> a ~> b

  -- | A catch on 'Category's.
  catchT :: (a ~> b) -> (String -> (a ~> b)) -> (a ~> b)


-- | Left-biased choice.
(<+) :: CategoryCatch (~>) => (a ~> b) -> (a ~> b) -> (a ~> b)
f <+ g = f `catchT` \ _ -> g

-- | Look at the argument to the 'Arrow' before choosing which 'Arrow' to use.
readerT :: ArrowApply (~>) => (a -> (a ~> b)) -> (a ~> b)
readerT f = (f &&& id) ^>> app

-- | Look at the argument to an 'Arrow', and choose to be either the identity arrow or a failure.
acceptR :: (CategoryCatch (~>), ArrowApply (~>)) => (a -> Bool) -> String -> (a ~> a)
acceptR p msg = readerT $ \ a -> if p a then id else failT msg

-- | Look at the argument to an 'Arrow', and choose to be either the identity arrow or a failure.
--   This is a generalisation of 'acceptR' to any 'Arrow'.
accepterR :: (CategoryCatch (~>), ArrowApply (~>)) => (a ~> Bool) -> String -> (a ~> a)
accepterR t msg = forkFirst t >>> readerT (\ (b,a) -> if b then constant a else failT msg)

-- | Catch a failing 'CategoryCatch', making it into an identity.
tryR :: CategoryCatch (~>) => (a ~> a) -> (a ~> a)
tryR r = r <+ id

-- | Catch a failing 'Arrow', making it succeed with a Boolean flag.
--   Useful when defining 'Language.KURE.Walker.anyR' instances.
attemptR :: (CategoryCatch (~>), Arrow (~>)) => (a ~> a) -> (a ~> (Bool,a))
attemptR r = (r >>^ (True,)) <+ arr (False,)

-- | Makes an 'Arrow' fail if the result value equals the argument value.
changedR :: (CategoryCatch (~>), ArrowApply (~>), Eq a) => (a ~> a) -> (a ~> a)
changedR r = readerT (\ a -> r >>> acceptR (/=a) "changedR: value is unchanged")

-- | Repeat a 'CategoryCatch' until it fails, then return the result before the failure.
--   Requires at least the first attempt to succeed.
repeatR :: CategoryCatch (~>) => (a ~> a) -> (a ~> a)
repeatR r = r >>> tryR (repeatR r)

-- | Attempt two 'Arrow's in sequence, succeeding if one or both succeed.
(>+>) :: (CategoryCatch (~>), ArrowApply (~>)) => (a ~> a) -> (a ~> a) -> (a ~> a)
r1 >+> r2 = attemptR r1 >>> readerT (\ (b,_) -> snd ^>> if b then tryR r2 else r2)

-- | Sequence a list of 'Arrow's, succeeding if any succeed.
orR :: (CategoryCatch (~>), ArrowApply (~>)) => [a ~> a] -> (a ~> a)
orR = foldr (>+>) (failT "orR failed")

-- | Sequence a list of 'Category's, succeeding if all succeed.
andR :: Category (~>) => [a ~> a] -> (a ~> a)
andR = foldr (>>>) id

-- | Select the first 'CategoryCatch' that succeeds, discarding any thereafter.
catchesT :: CategoryCatch (~>) => [a ~> b] -> (a ~> b)
catchesT = foldr (<+) (failT "catchesT failed")

------------------------------------------------------------------------------------------

-- | Apply a pure function to the result of an 'Arrow'.
result :: Arrow (~>) => (b -> c) -> (a ~> b) -> (a ~> c)
result f a = a >>^ f

-- | Apply a pure function to the argument to an 'Arrow'.
argument :: Arrow (~>) => (a -> b) -> (b ~> c) -> (a ~> c)
argument f a = f ^>> a

-- | Apply an 'Arrow' to the first element of a pair, discarding the second element.
toFst :: Arrow (~>) => (a ~> b) -> ((a,x) ~> b)
toFst f = fst ^>> f

-- | Apply an 'Arrow' to the second element of a pair, discarding the first element.
toSnd :: Arrow (~>) => (a ~> b) -> ((x,a) ~> b)
toSnd f = snd ^>> f

-- | A pure 'Arrow' that swaps the elements of a pair.
swap :: Arrow (~>) => ((a,b) ~> (b,a))
swap = arr (\(a,b) -> (b,a))

-- | A pure 'Arrow' that duplicates its argument.
fork :: Arrow (~>) => (a ~> (a,a))
fork = arr (\a -> (a,a))

-- | Tag the result of an 'Arrow' with its argument.
forkFirst :: Arrow (~>) => (a ~> b) -> (a ~> (b , a))
forkFirst sf = fork >>> first sf

-- | Tag the result of an 'Arrow' with its argument.
forkSecond :: Arrow (~>) => (a ~> b) -> (a ~> (a , b))
forkSecond sf = fork >>> second sf

-- | An arrow with a constant result.
constant :: Arrow (~>) => b -> (a ~> b)
constant b = arr (const b)

-------------------------------------------------------------------------------
