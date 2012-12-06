{-# LANGUAGE TupleSections, FlexibleInstances #-}

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

import Prelude hiding (id , (.), foldr)

import Control.Monad
import Control.Category
import Control.Arrow

import Data.Foldable
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
{-# INLINE (<<+) #-}

-- | Select the first monadic computation that succeeds, discarding any thereafter.
catchesM :: (Foldable f, MonadCatch m) => f (m a) -> m a
catchesM = foldr (<<+) (fail "catchesM failed")
{-# INLINE catchesM #-}

-- | Catch a failing monadic computation, making it succeed with a constant value.
tryM :: MonadCatch m => a -> m a -> m a
tryM a ma = ma <<+ return a
{-# INLINE tryM #-}

-- | Catch a failing monadic computation, making it succeed with 'mempty'.
mtryM :: (MonadCatch m, Monoid a) => m a -> m a
mtryM = tryM mempty
{-# INLINE mtryM #-}

-- | Catch a failing monadic computation, making it succeed with an error message.
attemptM :: MonadCatch m => m a -> m (Either String a)
attemptM ma = liftM Right ma `catchM` (return . Left)
{-# INLINE attemptM #-}

-- | Determine if a monadic computation succeeds.
testM :: MonadCatch m => m a -> m Bool
testM ma = liftM (const True) ma <<+ return False
{-# INLINE testM #-}

-- | Fail if the 'Monad' succeeds; succeed with @()@ if it fails.
notM :: MonadCatch m => m a -> m ()
notM ma = ifM (testM ma) (fail "notM of success") (return ())
{-# INLINE notM #-}

-- | Modify the error message of a failing monadic computation.
--   Successful computations are unaffected.
modFailMsg :: MonadCatch m => (String -> String) -> m a -> m a
modFailMsg f ma = ma `catchM` (fail . f)
{-# INLINE modFailMsg #-}

-- | Set the error message of a failing monadic computation.
--   Successful computations are unaffected.
setFailMsg :: MonadCatch m => String -> m a -> m a
setFailMsg msg = modFailMsg (const msg)
{-# INLINE setFailMsg #-}

-- | Add a prefix to the error message of a failing monadic computation.
--   Successful computations are unaffected.
prefixFailMsg :: MonadCatch m => String -> m a -> m a
prefixFailMsg msg = modFailMsg (msg ++)
{-# INLINE prefixFailMsg #-}

-- | Use the given error message whenever a monadic pattern match failure occurs.
withPatFailMsg :: MonadCatch m => String -> m a -> m a
withPatFailMsg msg = modFailMsg (\ e -> if "Pattern match failure" `isPrefixOf` e then msg else e)
{-# INLINE withPatFailMsg #-}

------------------------------------------------------------------------------------------

-- | Similar to 'guard', but invokes 'fail' rather than 'mzero'.
guardMsg ::  Monad m => Bool -> String -> m ()
guardMsg b msg = unless b (fail msg)
{-# INLINE guardMsg #-}

-- | As 'guardMsg', but with a default error message.
guardM ::  Monad m => Bool -> m ()
guardM b = guardMsg b "guardM failed"
{-# INLINE guardM #-}

-- | if-then-else lifted over a monadic predicate.
ifM ::  Monad m => m Bool -> m a -> m a -> m a
ifM mb m1 m2 = do b <- mb
                  if b then m1 else m2
{-# INLINE ifM #-}

-- | If the monadic predicate holds then perform the monadic action, else fail.
whenM ::  Monad m => m Bool -> m a -> m a
whenM mb ma = ifM mb ma (fail "whenM: condition False")
{-# INLINE whenM #-}

-- | If the monadic predicate holds then fail, else perform the monadic action.
unlessM ::  Monad m => m Bool -> m a -> m a
unlessM mb ma = ifM mb (fail "unlessM: condition True") ma
{-# INLINE unlessM #-}

------------------------------------------------------------------------------------------

-- | 'Category's with failure and catching.
--   The following law is expected to hold:
--
-- > failT msg `catchT` f == f msg

class Category arr => CategoryCatch arr where
  -- | The failing 'Category'.
  failT :: String -> arr a b

  -- | A catch on 'Category's.
  catchT :: arr a b -> (String -> arr a b) -> arr a b


-- | Left-biased choice.
(<+) :: CategoryCatch arr => arr a b -> arr a b -> arr a b
f <+ g = f `catchT` \ _ -> g
{-# INLINE (<+) #-}

-- | Look at the argument to the 'Arrow' before choosing which 'Arrow' to use.
readerT :: ArrowApply arr => (a -> arr a b) -> arr a b
readerT f = (f &&& id) ^>> app
{-# INLINE readerT #-}

-- | Look at the argument to an 'Arrow', and choose to be either the identity arrow or a failure.
acceptR :: (CategoryCatch arr, ArrowApply arr) => (a -> Bool) -> String -> arr a a
acceptR p msg = readerT $ \ a -> if p a then id else failT msg
{-# INLINE acceptR #-}

-- | Look at the argument to an 'Arrow', and choose to be either the identity arrow or a failure.
--   This is a generalisation of 'acceptR' to any 'Arrow'.
accepterR :: (CategoryCatch arr, ArrowApply arr) => arr a Bool -> String -> arr a a
accepterR t msg = forkFirst t >>> readerT (\ (b,a) -> if b then constant a else failT msg)
{-# INLINE accepterR #-}

-- | Catch a failing 'CategoryCatch', making it into an identity.
tryR :: CategoryCatch arr => arr a a -> arr a a
tryR r = r <+ id
{-# INLINE tryR #-}

-- | Catch a failing 'Arrow', making it succeed with a Boolean flag.
--   Useful when defining 'Language.KURE.Walker.anyR' instances.
attemptR :: (CategoryCatch arr, Arrow arr) => arr a a -> arr a (Bool,a)
attemptR r = (r >>^ (True,)) <+ arr (False,)
{-# INLINE attemptR #-}

-- | Makes an 'Arrow' fail if the result value equals the argument value.
changedR :: (CategoryCatch arr, ArrowApply arr, Eq a) => arr a a -> arr a a
changedR r = readerT (\ a -> r >>> acceptR (/=a) "changedR: value is unchanged")
{-# INLINE changedR #-}

-- | Repeat a 'CategoryCatch' until it fails, then return the result before the failure.
--   Requires at least the first attempt to succeed.
repeatR :: CategoryCatch arr => arr a a -> arr a a
repeatR r = let go = r >>> tryR go
             in go
{-# INLINE repeatR #-}

-- | Attempt two 'Arrow's in sequence, succeeding if one or both succeed.
(>+>) :: (CategoryCatch arr, ArrowApply arr) => arr a a -> arr a a -> arr a a
r1 >+> r2 = attemptR r1 >>> readerT (\ (b,_) -> snd ^>> if b then tryR r2 else r2)
{-# INLINE (>+>) #-}

-- | Sequence a list of 'Arrow's, succeeding if any succeed.
orR :: (Foldable f, CategoryCatch arr, ArrowApply arr) => f (arr a a) -> arr a a
orR = foldr (>+>) (failT "orR failed")
{-# INLINE orR #-}

-- | Sequence a list of 'Category's, succeeding if all succeed.
andR :: (Foldable f, Category arr) => f (arr a a) -> arr a a
andR = foldr (>>>) id
{-# INLINE andR #-}

-- | Select the first 'CategoryCatch' that succeeds, discarding any thereafter.
catchesT :: (Foldable f, CategoryCatch arr) => f (arr a b) -> arr a b
catchesT = foldr (<+) (failT "catchesT failed")
{-# INLINE catchesT #-}

------------------------------------------------------------------------------------------

-- | Apply a pure function to the result of an 'Arrow'.
result :: Arrow arr => (b -> c) -> arr a b -> arr a c
result f a = a >>^ f
{-# INLINE result #-}

-- | Apply a pure function to the argument to an 'Arrow'.
argument :: Arrow arr => (a -> b) -> arr b c -> arr a c
argument f a = f ^>> a
{-# INLINE argument #-}

-- | Apply an 'Arrow' to the first element of a pair, discarding the second element.
toFst :: Arrow arr => arr a b -> arr (a,x) b
toFst f = fst ^>> f
{-# INLINE toFst #-}

-- | Apply an 'Arrow' to the second element of a pair, discarding the first element.
toSnd :: Arrow arr => arr a b -> arr (x,a) b
toSnd f = snd ^>> f
{-# INLINE toSnd #-}

-- | A pure 'Arrow' that swaps the elements of a pair.
swap :: Arrow arr => arr (a,b) (b,a)
swap = arr (\(a,b) -> (b,a))
{-# INLINE swap #-}

-- | A pure 'Arrow' that duplicates its argument.
fork :: Arrow arr => arr a (a,a)
fork = arr (\a -> (a,a))
{-# INLINE fork #-}

-- | Tag the result of an 'Arrow' with its argument.
forkFirst :: Arrow arr => arr a b -> arr a (b,a)
forkFirst sf = fork >>> first sf
{-# INLINE forkFirst #-}

-- | Tag the result of an 'Arrow' with its argument.
forkSecond :: Arrow arr => arr a b -> arr a (a,b)
forkSecond sf = fork >>> second sf
{-# INLINE forkSecond #-}

-- | An arrow with a constant result.
constant :: Arrow arr => b -> arr a b
constant b = arr (const b)
{-# INLINE constant #-}

-------------------------------------------------------------------------------
