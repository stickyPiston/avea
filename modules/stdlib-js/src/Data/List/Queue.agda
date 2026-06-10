module Data.List.Queue where

open import Data.List
open import Data.Nat
open import Data.Maybe
open import Data.Product

module Queue where
  open import Data.List using (null?) public

  private variable
    A : Set

  t : Set → Set
  t = List

  empty : t A
  empty = []

  enqueue : A → t A → t A
  enqueue a q = q ++ [ a ]
  {-# COMPILE JS enqueue = A => a => q => [...q, a] #-}

  dequeue : t A → Maybe (A × t A)
  dequeue [] = nothing
  dequeue (x ∷ q) = just (x , q)
  {-# COMPILE JS dequeue = A => q => {
    if (q.length) return a => a["just"]({ "_,_": b => b["_,_"](q[0], q.slice(1)) });
    else return a => a["nothing"]();
  } #-}

  peek : t A → Maybe A
  peek [] = nothing
  peek (x ∷ _) = just x

  skip : Nat → t A → t A
  skip = drop