module Data.Either where

open import Data.List
open import Effect.Functor
open import Effect.Applicative
open import Effect.Monad

private variable
  A B : Set

data Either A B : Set where
  left : A → Either A B
  right : B → Either A B

instance
  Functor-Either : Functor (Either A)
  Functor-Either = record
    { fmap = λ where
      f (left a) → left a
      f (right b) → right (f b)
    }
  
  Applicative-Either : Applicative (Either A)
  Applicative-Either = record
    { functor = Functor-Either
    ; pure = right
    ; _<*>_ = λ where
      (right f) (right a) → right (f a)
      (right f) (left b) → left b
      (left a) _ → left a
    }

  Monad-Either : Monad (Either A)
  Monad-Either = record
    { applicative = Applicative-Either
    ; _>>=_ = λ where
      (left a) _ → left a
      (right a) f → f a
    }

open Monad {{ ... }}

collect-either : List (Either A B) → Either A (List B)
collect-either = foldl (right []) λ acc e → (| snoc e acc |)