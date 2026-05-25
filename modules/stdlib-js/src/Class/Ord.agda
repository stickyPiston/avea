module Class.Ord where

open import Agda.Builtin.Int
open import Data.Nat using (Nat) ; import Data.Nat as Nat
import Agda.Builtin.Nat as Nat
open import Data.Bool
open import Data.Product
open import Function

private variable
  A B : Set

module Ordering where
  data t : Set where
    lt eq gt : t

  to-Int : t → Int
  to-Int lt = negsuc 0
  to-Int eq = pos 0
  to-Int gt = pos 1
open Ordering using (lt ; eq ; gt) public

record Ord (A : Set) : Set where
  field compare : A → A → Ordering.t
open Ord {{ ... }} public

min max : {{ Ord A }} → A → A → A
min a b = compare a b |> λ where
  lt → a ; eq → a ; gt → b

max a b = compare a b |> λ where
  lt → b ; eq → a ; gt → a

_>_ _<_ _≤_ _≥_ : {{ Ord A }} → A → A → Bool
a > b = compare a b |> λ { gt → true ; _ → false }
a ≥ b = compare a b |> λ { gt → true ; eq → true ; _ → false }
a < b = compare a b |> λ { lt → true ; _ → false }
a ≤ b = compare a b |> λ { lt → true ; eq → true ; _ → false }

instance
  Ord-Nat : Ord Nat
  Ord-Nat = record
    { compare = λ n m → 
        if n Nat.< m then lt
        else if n Nat.== m then eq
        else gt
    }

  Ord-× : {{ Ord A }} → {{ Ord B }} → Ord (A × B)
  Ord-× = record
    { compare = λ (a , b) (c , d) → compare a c |> λ where
      eq → compare b d
      ordering → ordering
    }