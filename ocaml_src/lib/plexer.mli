(* camlp4r *)
(***********************************************************************)
(*                                                                     *)
(*                             Camlp4                                  *)
(*                                                                     *)
(*                Daniel de Rauglaudre, INRIA Rocquencourt             *)
(*                                                                     *)
(*  Copyright 2007 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* This file has been generated by program: do not edit! *)

(** A lexical analyzer. *)

val gmake : unit -> (string * string) Token.glexer;;
   (** Some lexer provided. See the module [Token]. The tokens returned
       follow the Objective Caml and the Revised syntax lexing rules.

       The meaning of the tokens are:
-      * [("", s)] is the keyword [s].
-      * [("LIDENT", s)] is the ident [s] starting with a lowercase letter.
-      * [("UIDENT", s)] is the ident [s] starting with an uppercase letter.
-      * [("INT", s)] is an integer constant whose string source is [s].
-      * [("FLOAT", s)] is a float constant whose string source is [s].
-      * [("STRING", s)] is the string constant [s].
-      * [("CHAR", s)] is the character constant [s].
-      * [("QUOTATION", "t:s")] is a quotation [t] holding the string [s].
-      * [("ANTIQUOT", "t:s")] is an antiquotation [t] holding the string [s].
-      * [("EOI", "")] is the end of input.

       The associated token patterns in the EXTEND statement hold the
       same names than the first string (constructor name) of the tokens
       expressions above.

       Warning: the string associated with the constructor [STRING] is
       the string found in the source without any interpretation. In
       particular, the backslashes are not interpreted. For example, if
       the input is ["\n"] the string is *not* a string with one
       element containing the character "return", but a string of two
       elements: the backslash and the character ["n"]. To interpret
       a string use the function [Token.eval_string]. Same thing for
       the constructor [CHAR]: to get the character, don't get the
       first character of the string, but use the function
       [Token.eval_char].

       The lexer do not use global (mutable) variables: instantiations
       of [Plexer.gmake ()] do not perturb each other.  *)

val dollar_for_antiquotation : bool ref;;
   (** When True (default), the next call to [Plexer.make ()] returns a
       lexer where the dollar sign is used for antiquotations. If False,
       the dollar sign can be used as token. *)

val specific_space_dot : bool ref;;
   (** When False (default), the next call to [Plexer.make ()] returns a
       lexer where the dots can be preceded by spaces. If True, dots
       preceded by spaces return the keyword " ." (space dot), otherwise
       return the keyword "." (dot). *)

val no_quotations : bool ref;;
   (** When True, all lexers built by [Plexer.make ()] do not lex the
       quotation syntax any more. Default is False (quotations are
       lexed). *)
