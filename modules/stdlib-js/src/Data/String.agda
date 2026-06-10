module Data.String where

open import Agda.Builtin.String
  using (String ; primShowString ; primStringToList ; primStringFromList ; primStringAppend)
  renaming
    ( primStringEquality to _==_
    ) public

open import Agda.Builtin.String using (primStringAppend)
open import Data.Bool

infixl 10 _++_
_++_ : String → String → String
_++_ = primStringAppend

open import Data.List using (List)
open import Data.List.NonEmpty
open import Agda.Builtin.Nat

postulate _starts-with_ : String → String → Bool
{-# COMPILE JS _starts-with_ = s => pre => s.startsWith(pre) #-}

postulate slice : Nat → Nat → String → String
{-# COMPILE JS slice = start => end => s => s.slice(Number(start), Number(end)) #-}

postulate ∥_∥ : String → Nat
{-# COMPILE JS ∥_∥ = s => BigInt(s.length) #-}

postulate unlines : List String → String
{-# COMPILE JS unlines = xs => xs.join("\n") #-}

postulate intercalate : String → List String → String
{-# COMPILE JS intercalate = x => xs => xs.join(x) #-}

postulate _=~_ : String → String → Bool
{-# COMPILE JS _=~_ = s => r => new RegExp(r).test(s) #-}

postulate replace : String → String → String → String
{-# COMPILE JS replace = r => w => s => s.replaceAll(new RegExp(r, "g"), w) #-}

postulate split : String → String → NE.t String
{-# COMPILE JS split = s => b => {
  const [hd, ...tl] = s.split(b);
  return { "_:|_": y => y["_:|_"](hd, tl) };
} #-}

lines : String → NE.t String
lines s = split s "\n"

postulate trim : String → String
{-# COMPILE JS trim = s => s.trim() #-}

join : List String → String
join = intercalate ""
