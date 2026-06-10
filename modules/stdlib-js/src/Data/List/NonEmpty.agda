module Data.List.NonEmpty where

open import Data.List using (List ; _∷_ ; [] ; [_])
import Data.List as List
open import Data.Product
open import Data.Maybe

private variable
  A B : Set

module NonEmpty where
  record t A : Set where
    constructor _:|_
    field
      head : A
      tail : List A
  open t public

  infixl 4 _:|_

  snoc : List A → A → t A
  snoc [] a = a :| []
  snoc (x ∷ xs) a = x :| (xs List.++ [ a ]) 

  unsnoc : t A → List A × A
  unsnoc (a :| as) = List.unsnoc (a ∷ as) or-else ([] , a)

  map : (A → B) → t A → t B
  map f (a :| as) = f a :| List.map f as

  unzip : t (A × B) → t A × t B
  unzip ((a , b) :| l) = let as , bs = List.unzip l in (a :| as) , (b :| bs)

  from-List : List A → Maybe (t A)
  from-List [] = nothing
  from-List (a ∷ as) = just (a :| as)

  to-List : t A → List A
  to-List (a :| as) = a ∷ as
open NonEmpty using (_:|_) public

module NE = NonEmpty