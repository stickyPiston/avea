module Data.Either where

private variable
  A B : Set

data Either A B : Set where
  left : A → Either A B
  right : B → Either A B