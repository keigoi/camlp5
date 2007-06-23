(* camlp4r q_MLast.cmo ./pa_extfun.cmo *)
(* $Id$ *)
(* Copyright (c) INRIA 2007 *)

open Pretty;
open Pcaml.NewPrinters;
open Prtools;

value flag_expand_declare = ref False;
value flag_horiz_let_in = ref False;
value flag_sequ_begin_at_eol = ref True;

value flag_where_after_in = ref True;
value flag_where_after_let_eq = ref True;
value flag_where_after_match = ref True;
value flag_where_after_lparen = ref True;
value flag_where_after_field_eq = ref False;
value flag_where_in_sequences = ref False;
value flag_where_after_then = ref True;
value flag_where_after_value_eq = ref True;
value flag_where_after_arrow = ref True;

(* general functions *)

value is_infix = do {
  let infixes = Hashtbl.create 73 in
  List.iter (fun s -> Hashtbl.add infixes s True)
    ["!="; "&&"; "*"; "**"; "*."; "+"; "+."; "-"; "-."; "/"; "/."; "<"; "<=";
     "<>"; "="; "=="; ">"; ">="; "@"; "^"; "asr"; "land"; "lor"; "lsl"; "lsr";
     "lxor"; "mod"; "or"; "||"; "~-"; "~-."];
  fun s -> try Hashtbl.find infixes s with [ Not_found -> False ]
};

value is_keyword =
  let keywords = ["value"] in
  fun s -> List.mem s keywords
;

value has_special_chars s =
  if String.length s = 0 then False
  else
    match s.[0] with
    [ '0'..'9' | 'A'..'Z' | 'a'..'z' | '_' -> False
    | _ -> True ]
;

value rec is_irrefut_patt =
  fun
  [ <:patt< $lid:_$ >> -> True
  | <:patt< () >> -> True
  | <:patt< _ >> -> True
  | <:patt< ($x$ as $y$) >> -> is_irrefut_patt x && is_irrefut_patt y
  | <:patt< { $list:fpl$ } >> ->
      List.for_all (fun (_, p) -> is_irrefut_patt p) fpl
  | <:patt< ($p$ : $_$) >> -> is_irrefut_patt p
  | <:patt< ($list:pl$) >> -> List.for_all is_irrefut_patt pl
  | <:patt< ? $_$ >> -> True
  | <:patt< ? ($_$ = $_$) >> -> True
  | <:patt< ~ $_$ >> -> True
  | <:patt< ~ $_$ : $_$ >> -> True
  | _ -> False ]
;

value not_impl name ind b x k =
  let desc =
    if Obj.tag (Obj.repr x) = Obj.tag (Obj.repr "") then
      sprintf "\"%s\"" (Obj.magic x)
    else if Obj.is_block (Obj.repr x) then
      "tag = " ^ string_of_int (Obj.tag (Obj.repr x))
    else "int_val = " ^ string_of_int (Obj.magic x)
  in
  sprintf "%s\"pr_r, not impl: %s; %s\"%s" b name (String.escaped desc) k
;

value var_escaped ind b v k =
  let x =
    if is_infix v || has_special_chars v then "\\" ^ v
    else if is_keyword v then v ^ "__"
    else v
  in
  sprintf "%s%s%s" b x k
;

value cons_escaped ind b v k =
  let x =
    match v with
    [ " True" -> "True_"
    | " False" -> "False_"
    | _ -> v ]
  in
  sprintf "%s%s%s" b x k
;

value rec mod_ident ind b sl k =
  match sl with
  [ [] -> sprintf "%s%s" b k
  | [s] -> var_escaped ind b s k
  | [s :: sl] -> mod_ident ind (sprintf "%s%s." b s) sl k ]
;

value semi_after elem ind b x k = elem ind b x (sprintf ";%s" k);
value star_after elem ind b x k = elem ind b x (sprintf " *%s" k);
value op_after elem ind b (x, op) k = elem ind b x (sprintf "%s%s" op k);

value and_before elem ind b x k = elem ind (sprintf "%sand " b) x k;
value bar_before elem ind b x k = elem ind (sprintf "%s| " b) x k;

value operator ind left right sh b op x y k =
  let op = if op = "" then "" else " " ^ op in
  horiz_vertic
    (fun () ->
       sprintf "%s%s%s %s%s" b (left ind "" x "") op (right ind "" y "") k)
    (fun () ->
       let s1 = left ind b x op in
       let s2 = right (shi ind 2) (tab (shi ind 2)) y k in
       sprintf "%s\n%s" s1 s2)
;

value left_operator ind sh unfold next b x k =
  let xl =
    loop [] x "" where rec loop xl x op =
      match unfold x with
      [ Some (x1, op1, x2) -> loop [(x2, op) :: xl] x1 op1
      | None -> [(x, op) :: xl] ]
  in
  match xl with
  [ [(x, _)] -> next ind b x k
  | _ ->
      horiz_vertic (fun () -> hlist (op_after next) ind b xl k)
        (fun () -> plist next sh ind b xl k) ]
;

value right_operator ind sh unfold next b x k =
  let xl =
    loop [] x where rec loop xl x =
      match unfold x with
      [ Some (x1, op, x2) -> loop [(x1, op) :: xl] x2
      | None -> List.rev [(x, "") :: xl] ]
  in
  match xl with
  [ [(x, _)] -> next ind b x k
  | _ ->
      horiz_vertic (fun () -> hlist (op_after next) ind b xl k)
        (fun () -> plist next sh ind b xl k) ]
;

(*
 * Extensible printers
 *)

value expr ind b z k = pr_expr.pr_fun "top" ind b z k;
value patt ind b z k = pr_patt.pr_fun "top" ind b z k;
value ctyp ind b z k = pr_ctyp.pr_fun "top" ind b z k;
value str_item ind b z k = pr_str_item.pr_fun "top" ind b z k;
value sig_item ind b z k = pr_sig_item.pr_fun "top" ind b z k;
value module_expr ind b z k = pr_module_expr.pr_fun "top" ind b z k;
value module_type ind b z k = pr_module_type.pr_fun "top" ind b z k;
value expr_fun_args ge = Extfun.apply pr_expr_fun_args.val ge;

(* expression with adding the possible comment before *)
value comm_expr expr ind b z k =
  let ccc = comm_bef ind (MLast.loc_of_expr z) in
  sprintf "%s%s" ccc (expr ind b z k)
;

(* couple pattern/anytype with adding the possible comment before *)
value comm_patt_any f ind b z k =
  let ccc = comm_bef ind (MLast.loc_of_patt (fst z)) in
  sprintf "%s%s" ccc (f ind b z k)
;

value patt_as ind b z k =
  match z with
  [ <:patt< ($x$ as $y$) >> ->
      let p1 = patt ind b x "" in
      let p2 = patt ind "" y k in
      sprintf "%s as %s" p1 p2
  | z -> patt ind b z k ]
;

(* utilities specific to pr_r *)

(* Basic displaying of a 'binding' (let, value, expr or patt record field).
   The pretty printing is done correctly, but there are no syntax shortcuts
   (e.g. "let f = fun x -> y" is *not* shortened as "let f x = y"), nor
   pretty printing shortcuts (e.g.
       let f =
         do {
           ...
         }
   is not shortened as
       let f = do {
         ...
       }

   Some functions follow (some of them with '_binding' in their name) which
   use syntax or pretty printing shortcuts.
*)
value binding elem ind b (p, e) k =
  horiz_vertic
    (fun () ->
       sprintf "%s%s = %s%s" b (patt ind "" p "") (elem ind "" e "") k)
    (fun () ->
       sprintf "%s\n%s" (patt ind b p " =")
         (elem (shi ind 2) (tab (shi ind 2)) e k))
;

pr_expr_fun_args.val :=
  extfun Extfun.empty with
  [ <:expr< fun $p$ -> $e$ >> as z ->
      if is_irrefut_patt p then
        let (pl, e) = expr_fun_args e in
        ([p :: pl], e)
      else ([], z)
  | z -> ([], z) ]
;

value sequencify e =
  if not flag_sequ_begin_at_eol.val then None else flatten_sequence e
;

(* Pretty printing improvement (optional):
   - print the sequence beginner at end of previous lines,
     therefore printing the sequence with one tabulation less
   - example:
          value f x =
            do {
              ...
            }
     is printed :
          value f x = do {
            ...
          }
 *)
value sequence_box ind bfun expr el k =
  let s1 = bfun " do {" in
  let s2 =
    vlistl (semi_after (comm_expr expr))
      (comm_expr expr) (shi ind 2) (tab (shi ind 2)) el ""
  in
  let s3 = sprintf "%s%s%s" (tab ind) "}" k in
  sprintf "%s\n%s\n%s" s1 s2 s3
;

(* Pretty printing improvement (optional):
   - test a "let" binding can be displayed as "where"
 *)
value can_be_displayed_as_where e =
  match e with
  [ <:expr< let rec $p$ = $body$ in $e$ >> ->
      let e1 =
        loop e where rec loop =
          fun
          [ <:expr< $e$ $_$ >> -> loop e
          | e -> e ]
      in
      match (p, e1, body) with
      [ (<:patt< $lid:f$ >>, <:expr< $lid:g$ >>,
         <:expr< fun [ $list:_$ ] >>) ->
          if f = g then Some (p, e, body) else None
      | _ -> None ]
  | _ -> None ]
;

(* Pretty printing improvement (optional):
   - display a "let" binding with the "where" construct
*)
value rec where_binding ind b (p, e, body) k =
  let (pl, body) = expr_fun_args body in
  let pl = [p :: pl] in
  horiz_vertic
    (fun () ->
       sprintf "%s%s where rec %s = %s" b (expr ind "" e "")
         (hlist patt ind "" pl "") (expr ind "" body ""))
    (fun () ->
       let horiz_where k =
         sprintf "%s%s where rec %s =%s" b (expr ind "" e "")
           (hlist patt ind "" pl "") k
       in
       let vertic_where k =
         let s1 = expr ind b e "" in
         let s2 =
           hlist patt ind (sprintf "%swhere rec " (tab ind)) pl
             (sprintf " =%s" k)
         in
         sprintf "%s\n%s" s1 s2
       in
       match sequencify body with
       [ Some el ->
           let expr_wh =
             if flag_where_in_sequences.val then expr_wh else expr
           in
           sequence_box ind
             (fun k ->
                horiz_vertic (fun () -> horiz_where k)
                  (fun () -> vertic_where k))
             expr_wh el k
       | None ->
           let s1 =
             horiz_vertic (fun () -> horiz_where "")
               (fun () -> vertic_where "")
           in
           let s2 = comm_expr expr (shi ind 2) (tab (shi ind 2)) body k in
           sprintf "%s\n%s" s1 s2 ])

and expr_wh ind b e k =
  match can_be_displayed_as_where e with
  [ Some (p, e, body) -> where_binding ind b (p, e, body) k
  | None -> expr ind b e k ]
;

value sequence_box2 ind bfun el k =
  let expr_wh = if flag_where_in_sequences.val then expr_wh else expr in
  sequence_box ind bfun expr_wh el k
;

(* Pretty printing improvements (optional):
   - prints "field x = e" instead of "field = fun x -> e" in a record
   - if vertical and "e" is a sequence, put the "do {" at after the "="
   Cancellation of all these improvements could be done by changing calls
   to this function to a call to "binding expr" above.
*)
value record_binding ind b (p, e) k =
  let (pl, e) = expr_fun_args e in
  let pl = [p :: pl] in
  let expr_wh = if flag_where_after_field_eq.val then expr_wh else expr in
  horiz_vertic
    (fun () ->
       sprintf "%s%s = %s%s" b (hlist patt ind "" pl "") (expr_wh ind "" e "")
         k)
    (fun () ->
       match sequencify e with
       [ Some el ->
           sequence_box2 ind (fun k -> hlist patt ind b pl (sprintf " =%s" k))
             el k
       | None ->
           sprintf "%s\n%s" (hlist patt ind b pl " =")
             (expr_wh (shi ind 2) (tab (shi ind 2)) e k) ])
;

(* Pretty printing improvements (optional):
   - prints "value x = e" instead of "value = fun x -> e"
   - if vertical and "e" is a sequence, put the "do {" at after the "="
   - the continuation after the expression is optionally on next line if
     it not a sequence (see 'particularity for the parameter 'ko' below)
   - the expression after '=' is displayed with the 'where' statement if
     possible (expr_wh)
   - if "e" is a type constraint, put the constraint after the params. E.g.
        value f x y = (e : t)
     is displayed:
        value f x y : t = e
   Particularity for the parameter 'ko':
     It is of type option (bool * string). The boolean asks whether we
     want that a newline be displayed before the continuation string if
     the value binding is vertical (does not fit on the line). If False,
     the continuation string is displayed in the last (possibly alone) line
     of the value binding. The string is the continuation, which is the
     empty string if the ko value is None.
       If the expression is a sequence, with the sequence beginner after
     the "=", it is not taken into account, the continuation will always be
     in the same line than the sequence closer.
   Cancellation of all these improvements could be done by changing calls
   to this function to a call to "binding expr" above.
*)
value value_binding ind b (p, e) ko =
  let (pl, e) = expr_fun_args e in
  let (e, tyo) =
    match e with
    [ <:expr< ($e$ : $t$) >>  -> (e, Some t)
    | _ -> (e, None) ]
  in
  let pl = [p :: pl] in
  let expr_wh = if flag_where_after_value_eq.val then expr_wh else expr in
  horiz_vertic
    (fun () ->
       sprintf "%s%s%s = %s%s" b (hlist patt ind "" pl "")
         (match tyo with
          [ Some t -> sprintf " : %s" (ctyp ind "" t "")
          | None -> "" ])
         (expr_wh ind "" e "")
         (match ko with [ Some (_, k) -> k | None -> "" ]))
    (fun () ->
       match sequencify e with
       [ Some el ->
           sequence_box2 ind
             (fun k ->
                horiz_vertic
                  (fun () ->
                     sprintf "%s%s%s =%s" b (hlist patt ind "" pl "")
                       (match tyo with
                        [ Some t -> sprintf " : %s" (ctyp ind "" t "")
                        | None -> "" ])
                       k)
                  (fun () ->
                     sprintf "%s%s%s =%s" b (hlist patt ind "" pl "")
                       (match tyo with
                        [ Some t -> sprintf " : %s" (ctyp ind "" t "")
                        | None -> "" ])
                       k))
             el (match ko with [ Some (_, k) -> k | None -> "" ])
       | None ->
           let s1 =
             horiz_vertic
               (fun () ->
                  sprintf "%s%s%s =" b (hlist patt ind "" pl "")
                    (match tyo with
                     [ Some t -> sprintf " : %s" (ctyp ind "" t "")
                     | None -> "" ]))
               (fun () ->
                  let patt_tycon tyo ind b p k =
                    match tyo with
                    [ Some t -> patt ind b p (ctyp ind " : " t k)
                    | None -> patt ind b p k ]
                  in
                  let pl = List.map (fun p -> (p, "")) pl in
                  plistl patt (patt_tycon tyo) 4 ind b pl " =")
           in
           let s2 =
             comm_expr expr_wh (shi ind 2) (tab (shi ind 2)) e
               (match ko with [ Some (False, k) -> k | _ -> "" ])
           in
           let s3 =
             match ko with
             [ Some (True, k) -> sprintf "\n%s%s" (tab ind) k
             | _ -> "" ]
           in
           sprintf "%s\n%s%s" s1 s2 s3 ])
;

(* Pretty printing improvements (optional):
   - prints "let f x = e" instead of "let f = fun x -> e"
   - prints a newline before the "in" if last element not horizontal
   - the expression after '=' is displayed as 'where' if possible (expr_wh)
   Cancellation of all these improvements could be done by changing calls
   to this function to a call to "binding expr" above.
*)
value let_binding ind b (p, e) is_last =
  let (pl, e) = expr_fun_args e in
  let pl = [p :: pl] in
  let expr_wh = if flag_where_after_let_eq.val then expr_wh else expr in
  horiz_vertic
    (fun () ->
       sprintf "%s%s = %s%s" b (hlist patt ind "" pl "") (expr_wh ind "" e "")
         (if is_last then " in" else ""))
    (fun () ->
       let s =
         match sequencify e with
         [ Some el ->
             sequence_box2 ind
               (fun k -> hlist patt ind b pl (sprintf " =%s" k)) el ""
         | None ->
             let s1 = hlist patt ind b pl " =" in
             let s2 = comm_expr expr_wh (shi ind 2) (tab (shi ind 2)) e "" in
             sprintf "%s\n%s" s1 s2 ]
       in
       if is_last then sprintf "%s\n%sin" s (tab ind) else s)
;

value match_assoc ind b (p, w, e) k =
  let expr_wh = if flag_where_after_arrow.val then expr_wh else expr in
  horiz_vertic
    (fun () ->
       sprintf "%s%s%s -> %s%s" b (patt_as ind "" p "")
         (match w with
          [ Some e -> sprintf " when %s" (expr ind "" e "")
          | None -> "" ])
         (comm_expr expr ind "" e "") k)
    (fun () ->
       let patt_arrow k =
         match w with
         [ Some e ->
             horiz_vertic
               (fun () -> 
                  sprintf "%s%s when %s ->%s" b (patt_as ind "" p "")
                    (expr ind "" e "") k)
               (fun () ->
                  let s1 = patt_as ind b p "" in
                  let s2 =
                    horiz_vertic
                      (fun () ->
                         sprintf "%swhen %s ->%s" (tab ind) (expr ind "" e "")
                           k)
                      (fun () ->
                         let s1 = sprintf "%swhen" (tab ind) in
                         let s2 =
                           expr (shi ind 2) (tab (shi ind 2)) e
                             (sprintf " ->%s" k)
                         in
                         sprintf "%s\n%s" s1 s2)
                  in
                  sprintf "%s\n%s" s1 s2)
         | None -> patt_as ind b p (sprintf " ->%s" k) ]
       in
       match sequencify e with
       [ Some el ->
           sequence_box2 ind
             (fun k ->
                horiz_vertic (fun _ -> sprintf "\n") (fun () -> patt_arrow k))
                el k
       | None ->
           let s1 = patt_arrow "" in
           let s2 = comm_expr expr_wh (shi ind 2) (tab (shi ind 2)) e k in
           sprintf "%s\n%s" s1 s2 ])
;

value match_assoc_sh ind b pwe k = match_assoc (shi ind 2) b pwe k;

value match_assoc_list ind b pwel k =
  if pwel = [] then sprintf "%s[]%s" b k
  else
    vlist2 match_assoc_sh (bar_before match_assoc_sh) ind (sprintf "%s[ " b)
      pwel ("", sprintf " ]%s" k)
;

value rec make_expr_list =
  fun
  [ <:expr< [$x$ :: $y$] >> ->
      let (xl, c) = make_expr_list y in
      ([x :: xl], c)
  | <:expr< [] >> -> ([], None)
  | x -> ([], Some x) ]
;

value rec make_patt_list =
  fun
  [ <:patt< [$x$ :: $y$] >> ->
      let (xl, c) = make_patt_list y in
      ([x :: xl], c)
  | <:patt< [] >> -> ([], None)
  | x -> ([], Some x) ]
;

value type_var ind b (tv, (p, m)) k =
  sprintf "%s%s'%s%s" b (if p then "+" else if m then "-" else "") tv k
;

(* type_decl: particularity for the parameter 'ko' -> see 'value_binding' *)
value type_decl ind b ((_, tn), tp, te, cl) ko =
  horiz_vertic
    (fun () ->
       sprintf "%s%s%s = %s%s%s" b (var_escaped ind "" tn "")
         (if tp = [] then "" else sprintf " %s" (hlist type_var ind "" tp ""))
         (ctyp ind "" te "")
         (if cl = [] then "" else not_impl "type_decl cl" ind "" cl "")
         (match ko with [ Some (_, k) -> k | None -> "" ]))
    (fun () ->
       let s1 =
         horiz_vertic
           (fun () ->
              sprintf "%s%s%s =" b (var_escaped ind "" tn "")
                (if tp = [] then "" else
                 sprintf " %s" (hlist type_var ind "" tp "")))
           (fun () -> not_impl "type_decl vertic 1" ind b tn "")
       in
       let s2 =
         if cl = [] then
           ctyp (shi ind 2) (tab (shi ind 2)) te
             (match ko with [ Some (False, k) -> k | _ -> "" ])
         else
           horiz_vertic
             (fun () ->
                sprintf "%s%s%s%s" (tab (shi ind 2)) (ctyp ind "" te "")
                  (not_impl "type_decl cl 2" ind "" cl "") "")
             (fun () -> not_impl "type_decl vertic 2" ind "" tn "")
       in
       let s3 =
         match ko with
         [ Some (True, k) -> sprintf "\n%s%s" (tab ind) k
         | _ -> "" ]
       in
       sprintf "%s\n%s%s" s1 s2 s3)
;

value label_decl ind b (_, l, m, t) k =
  horiz_vertic
    (fun () ->
       sprintf "%s%s : %s%s%s" b l (if m then "mutable " else "")
         (ctyp ind "" t "") k)
    (fun () ->
       let s1 = sprintf "%s%s :%s" b l (if m then " mutable" else "") in
       let s2 = ctyp (shi ind 2) (tab (shi ind 2)) t k in
       sprintf "%s\n%s" s1 s2)
;

value cons_decl ind b (_, c, tl) k =
  if tl = [] then cons_escaped ind b c k
  else
    horiz_vertic
      (fun () ->
         sprintf "%s%s of %s%s" b c
           (hlist2 ctyp (and_before ctyp) ind "" tl ("", "")) k)
      (fun () ->
         let s1 = sprintf "%s%s of" b c in
         let s2 =
           horiz_vertic
             (fun () ->
                sprintf "%s%s%s" (tab (shi ind 4))
                  (hlist2 ctyp (and_before ctyp) ind "" tl ("", "")) k)
             (fun () ->
                let tl = List.map (fun t -> (t, " and")) tl in
                plist ctyp 2 (shi ind 4) (tab (shi ind 4)) tl k)
         in
         sprintf "%s\n%s" s1 s2)
;

value has_cons_with_params vdl = List.exists (fun (_, _, tl) -> tl <> []) vdl;

value rec get_else_if =
  fun
  [ <:expr< if $e1$ then $e2$ else $e3$ >> ->
      let (eel, e3) = get_else_if e3 in
      ([(e1, e2) :: eel], e3)
  | e -> ([], e) ]
;

(* Expressions displayed without spaces separating elements; special
   for expressions as strings or arrays indexes (x.[...] or x.(...)).
   Applied only if only containing +, -, *, /, integers and variables. *)
value expr_short ind b x k =
  let rec expr1 ind b x k =
    match x with
    [ <:expr< $lid:op$ $x$ $y$ >> ->
        if op = "+" || op = "-" then
          sprintf "%s%s%s%s%s" b (expr1 ind "" x "") op (expr2 ind "" y "") k
        else expr2 ind b x k
    | _ -> expr2 ind b x k ]
  and expr2 ind b x k =
    match x with
    [ <:expr< $lid:op$ $x$ $y$ >> ->
        if op = "*" || op = "/" then
          sprintf "%s%s%s%s%s" b (expr2 ind "" x "") op (expr3 ind "" y "") k
        else expr3 ind b x k
    | _ -> expr3 ind b x k ]
  and expr3 ind b x k =
    match x with
    [ <:expr< $lid:v$ >> ->
        if is_infix v || has_special_chars v then raise Exit
        else var_escaped ind b v k
    | <:expr< $int:s$ >> -> sprintf "%s%s%s" b s k
    | <:expr< $lid:op$ $_$ $_$ >> ->
        if List.mem op ["+"; "-"; "*"; "/"] then
          sprintf "%s(%s)%s" b (expr1 ind "" x "") k
        else raise Exit
    | _ -> raise Exit ]
  in
  try horiz_vertic (fun () -> expr1 ind b x k) (fun () -> raise Exit) with
  [ Exit -> expr ind b x k ]
;

(* definitions of printers by decreasing level *)

value ctyp_top =
  extfun Extfun.empty with
  [ <:ctyp< $x$ == $y$ >> ->
      fun curr next ind b k -> operator ind next next 2 b "==" x y k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value ctyp_arrow =
  extfun Extfun.empty with
  [ <:ctyp< $_$ -> $_$ >> as z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:ctyp< $x$ -> $y$ >> -> Some (x, " ->", y)
          | _ -> None ]
        in
        right_operator ind 2 unfold next b z k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value ctyp_apply =
  extfun Extfun.empty with
  [ <:ctyp< $_$ $_$ >> as z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:ctyp< $x$ $y$ >> -> Some (x, "", y)
          | _ -> None ]
        in
        left_operator ind 2 unfold next b z k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value ctyp_dot =
  extfun Extfun.empty with
  [ <:ctyp< $x$ . $y$ >> ->
      fun curr next ind b k -> curr ind (curr ind b x ".") y k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value ctyp_simple =
  extfun Extfun.empty with
  [ <:ctyp< { $list:ltl$ } >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             hlistl (semi_after label_decl) label_decl ind
               (sprintf "%s{ " b) ltl (sprintf " }%s" k))
          (fun () ->
             vlistl (semi_after label_decl) label_decl (shi ind 2)
               (sprintf "%s{ " b) ltl (sprintf " }%s" k))
  | <:ctyp< [ $list:vdl$ ] >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             if has_cons_with_params vdl then sprintf "\n"
             else
               hlist2 cons_decl (bar_before cons_decl) ind
                 (sprintf "%s[ " b) vdl ("", sprintf " ]%s" k))
          (fun () ->
             vlist2 cons_decl (bar_before cons_decl) ind
               (sprintf "%s[ " b) vdl ("", sprintf " ]%s" k))
  | <:ctyp< ($list:tl$) >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%s(%s)%s" b (hlistl (star_after ctyp) ctyp ind "" tl "")
               k)
          (fun () ->
             let tl = List.map (fun t -> (t, " *")) tl in
             plist ctyp 1 ind (sprintf "%s(" b) tl (sprintf ")%s" k))
  | <:ctyp< $lid:t$ >> ->
      fun curr next ind b k -> var_escaped ind b t k
  | <:ctyp< $uid:t$ >> ->
      fun curr next ind b k -> sprintf "%s%s%s" b t k
  | <:ctyp< ' $s$ >> ->
      fun curr next ind b k -> var_escaped ind (sprintf "%s'" b) s k
  | <:ctyp< _ >> ->
      fun curr next ind b k -> sprintf "%s_%s" b k
  | <:ctyp< ? $i$ : $t$ >> | <:ctyp< ~ $_$ : $t$ >> ->
      fun curr next ind b k ->
        failwith "labels not pretty printed (in type); add pr_ro.cmo"
  | <:ctyp< [ = $list:_$ ] >> | <:ctyp< [ > $list:_$ ] >> |
    <:ctyp< [ < $list:_$ ] >> | <:ctyp< [ < $list:_$ > $list:_$ ] >> ->
      fun curr next ind b k ->
        failwith "variants not pretty printed (in type); add pr_ro.cmo"
  | <:ctyp< $_$ $_$ >> | <:ctyp< $_$ -> $_$ >> as z ->
      fun curr next ind b k ->
        ctyp (shi ind 1) (sprintf "%s(" b) z (sprintf ")%s" k)
  | z ->
      fun curr next ind b k -> not_impl "ctyp" ind b z k ]
;

value expr_top =
  extfun Extfun.empty with
  [ <:expr< if $e1$ then $e2$ else $e3$ >> ->
      fun curr next ind b k ->
        let expr_wh = if flag_where_after_then.val then expr_wh else expr in
        horiz_vertic
         (fun () ->
            sprintf "%sif %s then %s else %s%s" b (expr ind "" e1 "")
              (expr ind "" e2 "") (expr ind "" e3 "") k)
         (fun () ->
            let if_then ind b_if e1 e2 =
              horiz_vertic
                (fun () ->
                   sprintf "%s%s then %s" b_if (expr ind "" e1 "")
                     (expr ind "" e2 ""))
                (fun () ->
                   let horiz_if_then k =
                     sprintf "%s%s then%s" b_if (expr ind "" e1 "") k
                   in
                   let vertic_if_then k =
                     let s1 = expr (shi ind 3) b_if e1 "" in
                     let s2 = sprintf "%sthen%s" (tab ind) k in
                     sprintf "%s\n%s" s1 s2
                   in
                   match sequencify e2 with
                   [ Some el ->
                       sequence_box2 ind
                         (fun k ->
                            horiz_vertic (fun () -> horiz_if_then k)
                              (fun () -> vertic_if_then k))
                          el ""
                   | None ->
                       let s1 =
                         horiz_vertic (fun () -> horiz_if_then "")
                           (fun () -> vertic_if_then "")
                       in
                       let s2 =
                         comm_expr expr_wh (shi ind 2) (tab (shi ind 2)) e2 ""
                       in
                       sprintf "%s\n%s" s1 s2 ])
            in
            let s1 = if_then ind (sprintf "%sif " b) e1 e2 in
            let (eel, e3) = get_else_if e3 in
            let s2 =
              loop eel where rec loop =
                fun
                [ [(e1, e2) :: eel] ->
                    sprintf "\n%s%s"
                      (if_then ind (sprintf "%selse if " (tab ind)) e1 e2)
                      (loop eel)
                | [] -> "" ]
            in
            let s3 =
              horiz_vertic
                (fun () ->
                   sprintf "%selse %s%s" (tab ind)
                     (comm_expr expr ind "" e3 "") k)
                (fun () ->
                   match sequencify e3 with
                   [ Some el ->
                       sequence_box2 ind
                         (fun k ->
                            horiz_vertic (fun () -> sprintf "\n")
                              (fun () -> sprintf "%selse%s" (tab ind) k))
                         el k
                   | None ->
                       let s =
                         comm_expr expr_wh (shi ind 2) (tab (shi ind 2)) e3 k
                       in
                       sprintf "%selse\n%s" (tab ind) s ])
            in
            sprintf "%s%s\n%s" s1 s2 s3)
  | <:expr< fun [ $list:pwel$ ] >> ->
      fun curr next ind b k ->
        match pwel with
        [ [(p1, None, e1)] when is_irrefut_patt p1 ->
            let (pl, e1) = expr_fun_args e1 in
            let pl = [p1 :: pl] in
            horiz_vertic
              (fun () ->
                 sprintf "%sfun %s -> %s%s" b (hlist patt ind "" pl "")
                   (expr ind "" e1 "") k)
              (fun () ->
                 let fun_arrow k =
                   let pl = List.map (fun p -> (p, "")) pl in
                   plist patt 4 ind (sprintf "%sfun " b) pl
                     (sprintf " ->%s" k)
                 in
                 match sequencify e1 with
                 [ Some el ->
                     sequence_box2 ind
                       (fun k ->
                          horiz_vertic (fun _ -> sprintf "\n")
                            (fun () -> fun_arrow k))
                       el k
                 | None ->
                     let s1 = fun_arrow "" in
                     let s2 = expr (shi ind 2) (tab (shi ind 2)) e1 k in
                     sprintf "%s\n%s" s1 s2 ])
        | [] -> sprintf "%sfun []%s" b k
        | pwel ->
            let s = match_assoc_list ind (tab ind) pwel k in
            sprintf "%sfun\n%s" b s ]
  | <:expr< try $e1$ with [ $list:pwel$ ] >> |
    <:expr< match $e1$ with [ $list:pwel$ ] >> as e ->
      fun curr next ind b k ->
        let expr_wh = if flag_where_after_match.val then expr_wh else expr in
        let op =
          match e with
          [ <:expr< try $_$ with [ $list:_$ ] >> -> "try"
          | _ -> "match" ]
        in
        match pwel with
        [ [(p, wo, e)] when is_irrefut_patt p ->
            horiz_vertic
              (fun () ->
                 sprintf "%s%s %s with %s%s" b op (expr_wh ind "" e1 "")
                   (match_assoc ind "" (p, wo, e) "") k)
              (fun () ->
                 match
                   horiz_vertic
                     (fun () ->
                        Some
                          (sprintf "%s%s %s with %s%s ->" b op
                             (expr_wh ind "" e1 "") (patt ind "" p "")
                             (match wo with
                              [ Some e -> expr ind " when" e ""
                              | None -> "" ])))
                      (fun () -> None)
                 with
                 [ Some s1 ->
                     let s2 = expr (shi ind 2) (tab (shi ind 2)) e k in
                     sprintf "%s\n%s" s1 s2
                 | None ->
                     let s1 =
                       match sequencify e1 with
                       [ Some el ->
                           sequence_box2 ind
                             (fun k -> sprintf "%s%s%s" b op k) el ""
                       | None ->
                           let s =
                             expr_wh (shi ind 2) (tab (shi ind 2)) e1 ""
                           in
                           sprintf "%s%s\n%s" b op s ]
                     in
                     let s2 =
                       match_assoc ind (sprintf "%swith " (tab ind))
                         (p, wo, e) k
                     in
                     sprintf "%s\n%s" s1 s2 ])
        | _ ->
            horiz_vertic
              (fun () ->
                 sprintf "%s%s %s with %s%s" b op (expr_wh ind "" e1 "")
                   (match_assoc_list ind "" pwel "") k)
              (fun () ->
                 let s1 =
                   horiz_vertic
                     (fun () ->
                        sprintf "%s%s %s with" b op (expr_wh ind "" e1 ""))
                     (fun () ->
                        let s =
                          match sequencify e1 with
                          [ Some el ->
                              sequence_box2 ind
                                (fun k ->
                                   horiz_vertic (fun _ -> sprintf "\n")
                                     (fun () -> sprintf "%s%s%s" b op k))
                                el ""
                          | None ->
                              let s =
                                expr_wh (shi ind 2) (tab (shi ind 2)) e1 ""
                              in
                              sprintf "%s%s\n%s" b op s ]
                        in
                        sprintf "%s\n%swith" s (tab ind))
                 in
                 let s2 = match_assoc_list ind (tab ind) pwel k in
                 sprintf "%s\n%s" s1 s2) ]
  | <:expr< let $opt:rf$ $list:pel$ in $e$ >> as ge ->
      fun curr next ind b k ->
        let expr_wh = if flag_where_after_in.val then expr_wh else expr in
        horiz_vertic
          (fun () ->
             if not flag_horiz_let_in.val then sprintf "\n"
             else
               sprintf "%slet %s%s %s%s" b (if rf then "rec " else "")
                 (hlist2 let_binding (and_before let_binding) ind "" pel
                    (False, True))
                 (expr ind "" e "") k)
          (fun () ->
             match flatten_sequence ge with
             [ Some el ->
                 let loc = MLast.loc_of_expr ge in
                 curr ind b <:expr< do { $list:el$ } >> k
             | None ->
                 let s1 =
                   vlist2 let_binding (and_before let_binding) ind
                     (sprintf "%slet %s" b (if rf then "rec " else ""))
                     pel (False, True)
                 in
                 let s2 = comm_expr expr_wh ind (tab ind) e k in
                 sprintf "%s\n%s" s1 s2 ])
  | <:expr< let module $s$ = $me$ in $e$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%slet module %s = %s in %s%s" b s
               (module_expr ind "" me "") (expr ind "" e "") k)
          (fun () ->
             let s1 =
               horiz_vertic
                 (fun () ->
                    sprintf "%slet module %s = %s in" b s
                      (module_expr ind "" me ""))
                 (fun () ->
                    let s1 = sprintf "%slet module %s =" b s in
                    let s2 =
                      module_expr (shi ind 2) (tab (shi ind 2)) me ""
                    in
                    let s3 = sprintf "%sin" (tab ind) in
                    sprintf "%s\n%s\n%s" s1 s2 s3)
             in
             let s2 = expr ind (tab ind) e k in
             sprintf "%s\n%s" s1 s2)
  | <:expr< do { $list:el$ } >> as ge ->
      fun curr next ind b k ->
        let el =
          match flatten_sequence ge with
          [ Some el -> el
          | None -> el ]
        in
        horiz_vertic
          (fun () ->
             sprintf "%sdo {%s%s%s}%s" b " "
               (hlistl (semi_after (comm_expr expr)) (comm_expr expr) ind ""
                  el "")
               " " k)
          (fun () ->
             sprintf "%sdo {%s%s%s}%s" b "\n"
               (vlistl (semi_after expr) expr (shi ind 2) (tab (shi ind 2)) el
                  "")
               ("\n" ^ tab ind) k)
  | <:expr< while $e1$ do { $list:el$ } >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%swhile %s do { %s }%s" b (curr ind "" e1 "")
               (hlistl (semi_after expr) expr ind "" el "") k)
          (fun () ->
             let s1 =
               horiz_vertic
                 (fun () -> sprintf "%swhile %s do {" b (curr ind "" e1 ""))
                 (fun () ->
                    let s1 = sprintf "%swhile" b in
                    let s2 = curr (shi ind 2) (tab (shi ind 2)) e1 "" in
                    let s3 = sprintf "%sdo {" (tab ind) in
                    sprintf "%s\n%s\n%s" s1 s2 s3)
             in
             let s2 =
               vlistl (semi_after expr) expr (shi ind 2) (tab (shi ind 2)) el
                 ""
             in
             let s3 = sprintf "%s}%s" (tab ind) k in
             sprintf "%s\n%s\n%s" s1 s2 s3)
  | <:expr< for $v$ = $e1$ $to:d$ $e2$ do { $list:el$ } >> ->
      fun curr next ind b k ->
        let el =
          match el with
          [ [e] ->
              match sequencify e with
              [ Some el -> el
              | None -> el ]
          | _ -> el ]
        in
        horiz_vertic
          (fun () ->
             sprintf "%sfor %s = %s %s %s do { %s }%s" b v
               (curr ind "" e1 "") (if d then "to" else "downto")
               (curr ind "" e2 "")
               (hlistl (semi_after expr) expr ind "" el "") k)
          (fun () ->
             let s1 =
               horiz_vertic
                 (fun () ->
                    sprintf "%sfor %s = %s %s %s do {" b v
                      (curr ind "" e1 "") (if d then "to" else "downto")
                      (curr ind "" e2 ""))
                 (fun () ->
                    let s1 =
                      curr ind (sprintf "%sfor %s = " b v) e1
                        (if d then " to" else " downto")
                    in
                    let s2 = curr (shi ind 4) (tab (shi ind 4)) e2 "" in
                    let s3 = sprintf "%sdo {" (tab ind) in
                    sprintf "%s\n%s\n%s" s1 s2 s3)
             in
             let s2 =
               vlist (semi_after expr) (shi ind 2) (tab (shi ind 2)) el ""
             in
             let s3 = sprintf "%s}%s" (tab ind) k in
             sprintf "%s\n%s\n%s" s1 s2 s3)
  | z ->
      fun curr next ind b k -> next ind b z k ]
;

value expr_assign =
  extfun Extfun.empty with
  [ <:expr< $x$ := $y$ >> ->
      fun curr next ind b k -> operator ind next expr 2 b ":=" x y k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value expr_or =
  extfun Extfun.empty with
  [ z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:expr< $lid:op$ $x$ $y$ >> ->
              if List.mem op ["||"; "or"] then Some (x, " ||", y) else None
          | _ -> None ]
        in
        right_operator ind 0 unfold next b z k ]
;

value expr_and =
  extfun Extfun.empty with
  [ z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:expr< $lid:op$ $x$ $y$ >> ->
              if List.mem op ["&&"; "&"] then Some (x, " &&", y) else None
          | _ -> None ]
        in
        right_operator ind 0 unfold next b z k ]
;

value expr_less =
  extfun Extfun.empty with
  [ <:expr< $lid:op$ $x$ $y$ >> as z ->
      fun curr next ind b k ->
        match op with
        [ "!=" | "<" | "<=" | "<>" | "=" | "==" | ">" | ">=" ->
            operator ind next next 0 b op x y k
        | _ -> next ind b z k ]
  | z -> fun curr next ind b k -> next ind b z k ]
;

value expr_concat =
  extfun Extfun.empty with
  [ z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:expr< $lid:op$ $x$ $y$ >> ->
              if List.mem op ["^"; "@"] then Some (x, " " ^ op, y) else None
          | _ -> None ]
        in
        right_operator ind 0 unfold next b z k ]
;

value expr_add =
  let ops = ["+"; "+."; "-"; "-."] in
  extfun Extfun.empty with
  [ z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:expr< $lid:op$ $x$ $y$ >> ->
              if List.mem op ops then Some (x, " " ^ op, y) else None
          | _ -> None ]
        in
        left_operator ind 0 unfold next b z k ]
;

value expr_mul =
  let ops = ["*"; "*."; "/"; "/."; "land"; "lor"; "lxor"; "mod"] in
  extfun Extfun.empty with
  [ z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:expr< $lid:op$ $x$ $y$ >> ->
              if List.mem op ops then Some (x, " " ^ op, y) else None
          | _ -> None ]
        in
        left_operator ind 0 unfold next b z k ]
;

value expr_pow =
  let ops = ["**"; "asr"; "lsl"; "lsr"] in
  extfun Extfun.empty with
  [ z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:expr< $lid:op$ $x$ $y$ >> ->
              if List.mem op ops then Some (x, " " ^ op, y) else None
          | _ -> None ]
        in
        right_operator ind 0 unfold next b z k ]
;

value expr_unary_minus =
  extfun Extfun.empty with
  [ <:expr< ~- $x$ >> ->
      fun curr next ind b k -> curr ind (sprintf "%s-" b) x k
  | <:expr< ~-. $x$ >> ->
      fun curr next ind b k -> curr ind (sprintf "%s-." b) x k
  | <:expr< $int:i$ >> ->
      fun curr next ind b k -> sprintf "%s%s%s" b i k
  | z ->
      fun curr next ind b k -> next ind b z k ]
;

value expr_apply =
  extfun Extfun.empty with
  [ <:expr< assert $e$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () -> sprintf "%sassert %s%s" b (next ind "" e "") k)
          (fun () -> not_impl "assert vertical" ind b e k)
  | <:expr< lazy $e$ >> ->
      fun curr next ind b k ->
        horiz_vertic (fun () -> sprintf "%slazy %s%s" b (next ind "" e "") k)
          (fun () ->
             let s1 = sprintf "%slazy" b in
             let s2 = next (shi ind 2) (tab (shi ind 2)) e k in
             sprintf "%s\n%s" s1 s2)
  | <:expr< $_$ $_$ >> as z ->
      fun curr next ind b k ->
        let inf =
          match z with
          [ <:expr< $lid:n$ $_$ $_$ >> -> is_infix n
          | <:expr< [$_$ :: $_$] >> -> True
          | _ -> False ]
        in
        if inf then next ind b z k
        else
          let unfold =
            fun
            [ <:expr< $x$ $y$ >> -> Some (x, "", y)
            | e -> None ]
          in
          left_operator ind 2 unfold next b z k
  | z ->
      fun curr next ind b k -> next ind b z k ]
;

value expr_dot =
  extfun Extfun.empty with
  [ <:expr< $x$ . $y$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%s%s.%s%s" b (curr ind "" x "") (curr ind "" y "") k)
          (fun () ->
             let s1 = curr ind b x "." in
             let s2 = curr ind (tab ind) y k in
             sprintf "%s\n%s" s1 s2)
  | <:expr< $x$ .( $y$ ) >> ->
      fun curr next ind b k ->
        expr ind (curr ind b x ".(") y (sprintf ")%s" k)
  | <:expr< $x$ .[ $y$ ] >> ->
      fun curr next ind b k ->
        expr_short ind (curr ind b x ".[") y (sprintf "]%s" k)
  | z ->
      fun curr next ind b k -> next ind b z k ]
;

value expr_simple =
  extfun Extfun.empty with
  [ <:expr< ($list:el$) >> ->
      fun curr next ind b k ->
        let el = List.map (fun e -> (e, ",")) el in
        plist expr 1 ind (sprintf "%s(" b) el (sprintf ")%s" k)
  | <:expr< {$list:lel$} >> ->
      fun curr next ind b k ->
        let lxl = List.map (fun lx -> (lx, ";")) lel in
        plist (comm_patt_any record_binding) 0 (shi ind 1) (sprintf "%s{" b)
          lxl (sprintf "}%s" k)
  | <:expr< {($e$) with $list:lel$} >> ->
      fun curr next ind b k ->
        let lxl = List.map (fun lx -> (lx, ";")) lel in
        plist record_binding 0 (shi ind 1)
          (expr ind (sprintf "%s{(" b) e ") with ") lxl
          (sprintf "}%s" k)
  | <:expr< [| $list:el$ |] >> ->
      fun curr next ind b k ->
        if el = [] then sprintf "%s[| |]%s" b k
        else
          let el = List.map (fun e -> (e, ";")) el in
          plist expr 0 (shi ind 3) (sprintf "%s[| " b) el (sprintf " |]%s" k)
  | <:expr< [$_$ :: $_$] >> as z ->
      fun curr next ind b k ->
        let (xl, y) = make_expr_list z in
        let xl = List.map (fun x -> (x, ";")) xl in
        let expr2 ind b x k =
          match y with
          [ Some y ->
              horiz_vertic
                (fun () ->
                   sprintf "%s%s :: %s]%s" b (expr ind "" x "")
                     (expr ind "" y "") k)
                (fun () ->
                   let s1 = expr ind b x " ::" in
                   let s2 = expr ind (tab ind) y (sprintf "]%s" k) in
                   sprintf "%s\n%s" s1 s2)
          | None -> expr ind b x (sprintf "]%s" k) ]
        in
        plistl expr expr2 0 (shi ind 1) (sprintf "%s[" b) xl k
  | <:expr< ($e$ : $t$) >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%s(%s : %s)%s" b (expr ind "" e "") (ctyp ind "" t "")
               k)
          (fun () ->
             let s1 = expr (shi ind 1) (sprintf "%s(" b) e " :" in
             let s2 =
               ctyp (shi ind 1) (tab (shi ind 1)) t (sprintf ")%s" k)
             in
             sprintf "%s\n%s" s1 s2)
  | <:expr< $int:s$ >> | <:expr< $flo:s$ >> ->
      fun curr next ind b k ->
        if String.length s > 0 && s.[0] = '-' then sprintf "%s(%s)%s" b s k
        else sprintf "%s%s%s" b s k
  | <:expr< $int32:s$ >> ->
      fun curr next ind b k ->
        let s = s ^ "l" in
        if String.length s > 0 && s.[0] = '-' then sprintf "%s(%s)%s" b s k
        else sprintf "%s%s%s" b s k
  | <:expr< $int64:s$ >> ->
      fun curr next ind b k ->
        let s = s ^ "L" in
        if String.length s > 0 && s.[0] = '-' then sprintf "%s(%s)%s" b s k
        else sprintf "%s%s%s" b s k
  | <:expr< $nativeint:s$ >> ->
      fun curr next ind b k ->
        let s = s ^ "n" in
        if String.length s > 0 && s.[0] = '-' then sprintf "%s(%s)%s" b s k
        else sprintf "%s%s%s" b s k
  | <:expr< $lid:s$ >> ->
      fun curr next ind b k -> var_escaped ind b s k
  | <:expr< $uid:s$ >> ->
      fun curr next ind b k -> cons_escaped ind b s k
  | <:expr< `$uid:s$ >> ->
      fun curr next ind b k -> sprintf "%s%s%s" b s k
  | <:expr< $str:s$ >> ->
      fun curr next ind b k -> sprintf "%s\"%s\"%s" b s k
  | <:expr< $chr:s$ >> ->
      fun curr next ind b k -> sprintf "%s'%s'%s" b s k
  | <:expr< ? $_$ >> | <:expr< ~ $_$ >> | <:expr< ~ $_$ : $_$ >> ->
      fun curr next ind b k ->
        failwith "labels not pretty printed (in expr); add pr_ro.cmo"
  | <:expr< $_$ $_$ >> | <:expr< assert $_$ >> | <:expr< lazy $_$ >> |
    <:expr< $_$ := $_$ >> |
    <:expr< fun [ $list:_$ ] >> | <:expr< if $_$ then $_$ else $_$ >> |
    <:expr< do { $list:_$ } >> |
    <:expr< for $_$ = $_$ $to:_$ $_$ do { $list:_$ } >> |
    <:expr< while $_$ do { $list:_$ } >> |
    <:expr< let $opt:_$ $list:_$ in $_$ >> |
    <:expr< match $_$ with [ $list:_$ ] >> |
    <:expr< try $_$ with [ $list:_$ ] >> as z ->
      fun curr next ind b k ->
        let expr_wh = if flag_where_after_lparen.val then expr_wh else expr in
        expr_wh (shi ind 1) (sprintf "%s(" b) z (sprintf ")%s" k)
  | z ->
      fun curr next ind b k -> not_impl "expr" ind b z k ]
;

value patt_top =
  extfun Extfun.empty with
  [ <:patt< $_$ | $_$ >> as z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:patt< $x$ | $y$ >> -> Some (x, " |", y)
          | _ -> None ]
        in
        left_operator ind 0 unfold next b z k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value patt_range =
  extfun Extfun.empty with
  [ <:patt< $x$ .. $y$ >> ->
      fun curr next ind b k ->
        sprintf "%s..%s" (next ind b x "") (next ind "" y k)
  | z -> fun curr next ind b k -> next ind b z k ]
;

value patt_apply =
  extfun Extfun.empty with
  [ <:patt< $_$ $_$ >> as z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:patt< [ $_$ :: $_$ ] >> -> None
          | <:patt< $x$ $y$ >> -> Some (x, "", y)
          | p -> None ]
        in
        left_operator ind 2 unfold next b z k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value patt_dot =
  extfun Extfun.empty with
  [ <:patt< $x$ . $y$ >> ->
      fun curr next ind b k -> curr ind (curr ind b x ".") y k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value patt_simple =
  extfun Extfun.empty with
  [ <:patt< ($x$ as $y$) >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%s(%s as %s)%s" b (patt ind "" x "") (patt ind "" y "")
               k)
          (fun () ->
             let s1 = patt (shi ind 1) (sprintf "%s(" b) x "" in
             let s2 =
               patt (shi ind 1) (sprintf "%sas " (tab (shi ind 1))) y
                 (sprintf ")%s" k)
             in
             sprintf "%s\n%s" s1 s2)
  | <:patt< ($list:pl$) >> ->
      fun curr next ind b k ->
        let pl = List.map (fun p -> (p, ",")) pl in
        plist patt 1 ind (sprintf "%s(" b) pl (sprintf ")%s" k)
  | <:patt< {$list:lpl$} >> ->
      fun curr next ind b k ->
        let lxl = List.map (fun lx -> (lx, ";")) lpl in
        plist (binding patt) 0 (shi ind 1) (sprintf "%s{" b) lxl
          (sprintf "}%s" k)
  | <:patt< [$_$ :: $_$] >> as z ->
      fun curr next ind b k ->
        let (xl, y) = make_patt_list z in
        let xl = List.map (fun x -> (x, ";")) xl in
        let patt2 ind b x k =
          match y with
          [ Some y ->
              horiz_vertic
                (fun () ->
                   sprintf "%s%s :: %s]%s" b (patt ind "" x "")
                     (patt ind "" y "") k)
                (fun () ->
                   let s1 = patt ind b x " ::" in
                   let s2 =
                     patt (shi ind 2) (tab (shi ind 2)) y (sprintf "]%s" k)
                   in
                   sprintf "%s\n%s" s1 s2)
          | None -> patt ind b x (sprintf "]%s" k) ]
        in
        plistl patt patt2 0 (shi ind 1) (sprintf "%s[" b) xl k
  | <:patt< ($p$ : $t$) >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%s(%s : %s)%s" b (patt ind "" p "") (ctyp ind "" t "")
               k)
          (fun () ->
             let s1 = patt ind (sprintf "%s(" b) p " :" in
             let s2 =
               ctyp (shi ind 1) (tab (shi ind 1)) t (sprintf ")%s" k)
             in
             sprintf "%s\n%s" s1 s2)
  | <:patt< $int:s$ >> ->
      fun curr next ind b k -> sprintf "%s%s%s" b s k
  | <:patt< $lid:s$ >> ->
      fun curr next ind b k -> var_escaped ind b s k
  | <:patt< $uid:s$ >> ->
      fun curr next ind b k -> cons_escaped ind b s k
  | <:patt< $chr:s$ >> ->
      fun curr next ind b k -> sprintf "%s'%s'%s" b s k
  | <:patt< $str:s$ >> ->
      fun curr next ind b k -> sprintf "%s\"%s\"%s" b s k
  | <:patt< _ >> ->
      fun curr next ind b k -> sprintf "%s_%s" b k
  | <:patt< ? $_$ >> | <:patt< ? ($_$ $opt:_$) >> |
    <:patt< ? $_$ : ($_$ $opt:_$) >> | <:patt< ~ $_$ >> |
    <:patt< ~ $_$ : $_$ >> ->
      fun curr next ind b k ->
        failwith "labels not pretty printed (in patt); add pr_ro.cmo"
  | <:patt< `$uid:s$ >> ->
      fun curr next ind b k ->
        failwith "polymorphic variants not pretty printed; add pr_ro.cmo"
  | <:patt< $_$ $_$ >> | <:patt< $_$ | $_$ >> | <:patt< $_$ .. $_$ >>
    as z ->
      fun curr next ind b k ->
        patt (shi ind 1) (sprintf "%s(" b) z (sprintf ")%s" k)
  | z ->
      fun curr next ind b k -> not_impl "patt" ind b z k ]
;

value string ind b s k = sprintf "%s\"%s\"%s" b s k;

value external_decl ind b (n, t, sl) k =
  horiz_vertic
    (fun () ->
       sprintf "%sexternal %s : %s = %s%s" b (var_escaped ind "" n "")
         (ctyp ind "" t "") (hlist string ind "" sl "") k)
    (fun () ->
       let s1 = var_escaped ind (sprintf "%sexternal " b) n " :" in
       let s2 =
         ctyp (shi ind 2) (tab (shi ind 2)) t
           (if sl = [] then k
            else sprintf " = %s%s" (hlist string ind "" sl "") k)
       in
       sprintf "%s\n%s" s1 s2)
;

value exception_decl ind b (e, tl, id) k =
  horiz_vertic
    (fun () ->
       sprintf "%sexception %s%s%s%s" b e
         (if tl = [] then ""
          else
            sprintf " of %s" (hlist2 ctyp (and_before ctyp) ind "" tl
              ("", "")))
         (if id = [] then ""
          else sprintf " = %s" (mod_ident ind "" id ""))
         k)
    (fun () ->
       let s1 =
         sprintf "%sexception %s%s" b e (if tl = [] then "" else " of")
       in
       let s2 =
         if tl = [] then ""
         else
           let tl = List.map (fun t -> (t, " and")) tl in
           sprintf "\n%s"
             (plist ctyp 2 ind (tab (shi ind 2)) tl
                (if id = [] then k else ""))
       in
       let s3 =
         if id = [] then ""
         else
           sprintf "\n%s"
             (mod_ident (shi ind 2) (sprintf "%s= " (tab (shi ind 2))) id k)
       in
       sprintf "%s%s%s" s1 s2 s3)
;

value str_item_top =
  extfun Extfun.empty with
  [ <:str_item< # $s$ $e$ >> ->
      fun curr next ind b k -> expr ind (sprintf "%s#%s " b s) e k
  | <:str_item< declare $list:sil$ end >> ->
      fun curr next ind b k ->
        if flag_expand_declare.val then
          horiz_vertic (fun () -> hlist (semi_after str_item) ind "" sil "")
            (fun () -> not_impl "expand declare vertic" ind b sil k)
        else if sil = [] then sprintf "%sdeclare end%s" b k
        else
          horiz_vertic
            (fun () ->
               sprintf "%sdeclare%s%s%send%s" b " "
                 (hlist (semi_after str_item) ind "" sil "")
                 " " k)
            (fun () ->
               sprintf "%sdeclare%s%s%send%s" b "\n"
                 (vlist (semi_after str_item) (shi ind 2) (tab (shi ind 2))
                    sil "")
                 ("\n" ^ tab ind) k)
  | <:str_item< exception $e$ of $list:tl$ = $id$ >> ->
      fun curr next ind b k -> exception_decl ind b (e, tl, id) k
  | <:str_item< external $n$ : $t$ = $list:sl$ >> ->
      fun curr next ind b k -> external_decl ind b (n, t, sl) k
  | <:str_item< include $me$ >> ->
      fun curr next ind b k -> module_expr ind (sprintf "%sinclude " b) me k
  | <:str_item< module $m$ = $me$ >> ->
      fun curr next ind b k ->
        let (mal, me) =
          loop me where rec loop =
            fun
            [ <:module_expr< functor ($s$ : $mt$) -> $me$ >> ->
                let (mal, me) = loop me in
                ([(s, mt) :: mal], me)
            | me -> ([], me) ]
        in
        let module_arg ind b (s, mt) k =
          horiz_vertic
            (fun () ->
               sprintf "%s(%s : %s)%s" b s (module_type ind "" mt "") k)
            (fun () ->
               let s1 = sprintf "%s(%s :" b s in
               let s2 =
                 module_type (shi ind 1) (tab (shi ind 1)) mt
                   (sprintf ")%s" k)
               in
               sprintf "%s\n%s" s1 s2)
        in
        let (me, mto) =
          match me with
          [ <:module_expr< ($me$ : $mt$) >> -> (me, Some mt)
          | _ -> (me, None) ]
        in
        horiz_vertic
          (fun () ->
             sprintf "%smodule %s%s%s = %s%s" b m
               (if mal = [] then "" else hlist module_arg ind " " mal "")
               (match mto with
                [ Some mt -> sprintf " : %s" (module_type ind "" mt "")
                | None -> "" ])
               (module_expr ind "" me "") k)
          (fun () ->
             let s1 =
               match mto with
               [ Some mt ->
                   horiz_vertic
                     (fun () ->
                        sprintf "%smodule %s%s : %s =" b m
                          (if mal = [] then ""
                           else hlist module_arg ind " " mal "")
                          (module_type ind "" mt ""))
                     (fun () ->
                        let s1 =
                          sprintf "%smodule %s%s :" b m
                            (if mal = [] then "" else
                             hlist module_arg ind " " mal "")
                        in
                        let s2 =
                          module_type (shi ind 2) (tab (shi ind 2)) mt " ="
                        in
                        sprintf "%s\n%s" s1 s2)
               | None ->
                   let mal = List.map (fun ma -> (ma, "")) mal in
                   plistb module_arg 2 ind (sprintf "%smodule %s" b m) mal
                     " =" ]
             in
             let s2 = module_expr (shi ind 2) (tab (shi ind 2)) me "" in
             sprintf "%s\n%s\n%s" s1 s2 (tab ind ^ k))
  | <:str_item< module type $m$ = $mt$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%smodule type %s = %s%s" b m (module_type ind "" mt "")
               k)
          (fun () ->
             let s1 = sprintf "%smodule type %s =" b m in
             let s2 = module_type (shi ind 2) (tab (shi ind 2)) mt "" in
             let s3 = sprintf "%s%s" (tab ind) k in
             sprintf "%s\n%s\n%s" s1 s2 s3)
  | <:str_item< open $i$ >> ->
      fun curr next ind b k -> mod_ident ind (sprintf "%sopen " b) i k
  | <:str_item< type $list:tdl$ >> ->
      fun curr next ind b k ->
        vlist2 type_decl (and_before type_decl) ind (sprintf "%stype " b) tdl
          (None, Some (True, k))
  | <:str_item< value $opt:rf$ $list:pel$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%svalue %s%s" b (if rf then "rec " else "")
               (hlist2 value_binding (and_before value_binding) ind "" pel
                  (None, Some (False, k))))
          (fun () ->
             vlist2 value_binding (and_before value_binding) ind
               (sprintf "%svalue %s" b (if rf then "rec " else "")) pel
               (None, Some (True, k)))
  | <:str_item< $exp:e$ >> ->
      fun curr next ind b k -> expr ind b e k
  | <:str_item< class type $list:_$ >> | <:str_item< class $list:_$ >> ->
      fun curr next ind b k ->
        failwith "classes and objects not pretty printed; add pr_ro.cmo"
  | z ->
      fun curr next ind b k -> not_impl "str_item" ind b z k ]
;

value sig_item_top =
  extfun Extfun.empty with
  [ <:sig_item< exception $e$ of $list:tl$ >> ->
      fun curr next ind b k -> exception_decl ind b (e, tl, []) k
  | <:sig_item< external $n$ : $t$ = $list:sl$ >> ->
      fun curr next ind b k -> external_decl ind b (n, t, sl) k
  | <:sig_item< module $m$ : $mt$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%smodule %s : %s%s" b m (module_type ind "" mt "") k)
          (fun () ->
             sprintf "%smodule %s :\n%s\n%s" b m
               (module_type (shi ind 2) (tab (shi ind 2)) mt "")
                  (tab ind ^ k))
  | <:sig_item< module type $m$ = $mt$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%smodule type %s = %s%s" b m (module_type ind "" mt "")
               k)
          (fun () ->
             let s1 = sprintf "%smodule type %s =" b m in
             let s2 = module_type (shi ind 2) (tab (shi ind 2)) mt "" in
             let s3 = sprintf "%s%s" (tab ind) k in
             sprintf "%s\n%s\n%s" s1 s2 s3)
  | <:sig_item< open $i$ >> ->
      fun curr next ind b k -> mod_ident ind (sprintf "%sopen " b) i k
  | <:sig_item< type $list:tdl$ >> ->
      fun curr next ind b k ->
        vlist2 type_decl (and_before type_decl) ind (sprintf "%stype " b) tdl
          (None, Some (True, k))
  | <:sig_item< value $s$ : $t$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%svalue %s : %s%s" b (var_escaped ind "" s "")
               (ctyp ind "" t "") k)
          (fun () ->
             let s1 = sprintf "%svalue %s :" b (var_escaped ind "" s "") in
             let s2 = ctyp (shi ind 2) (tab (shi ind 2)) t k in
             sprintf "%s\n%s" s1 s2)
  | <:sig_item< class type $list:_$ >> | <:sig_item< class $list:_$ >> ->
      fun curr next ind b k ->
        failwith "classes and objects not pretty printed; add pr_ro.cmo"
  | z ->
      fun curr next ind b k -> not_impl "sig_item" ind b z k ]
;

value module_expr_top =
  extfun Extfun.empty with
  [ <:module_expr< functor ($s$ : $mt$) -> $me$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%sfunctor (%s: %s) -> %s%s" b s
               (module_type ind "" mt "") (module_expr ind "" me "") k)
          (fun () ->
             let s1 =
               horiz_vertic
                 (fun () ->
                    sprintf "%sfunctor (%s : %s) ->" b s
                      (module_type ind "" mt ""))
                 (fun () ->
                    let s1 = sprintf "%sfunctor" b in
                    let s2 =
                      horiz_vertic
                        (fun () ->
                           sprintf "%s(%s : %s)" (tab (shi ind 2)) s
                             (module_type ind "" mt ""))
                        (fun () ->
                           let s1 = sprintf "%s(%s :" (tab (shi ind 2)) s in
                           let s2 =
                             module_type (shi ind 3) (tab (shi ind 3)) mt ")"
                           in
                           sprintf "%s\n%s" s1 s2)
                    in
                    let s3 = sprintf "%s->" (tab ind) in
                    sprintf "%s\n%s\n%s" s1 s2 s3)
             in
             let s2 = module_expr (shi ind 2) (tab (shi ind 2)) me k in
             sprintf "%s\n%s" s1 s2)
  | <:module_expr< struct $list:sil$ end >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             if loop 0 where rec loop i =
                  if i >= String.length b then True
                  else if b.[i] = ' ' then loop (i + 1)
                  else False
             then
               (* Heuristic : I don't like to print structs horizontally
                  when starting a line. *)
               sprintf "\n"
             else
               sprintf "%sstruct%s%s%send%s" b " "
                 (hlist (semi_after str_item) ind "" sil "")
                 " " k)
          (fun () ->
             sprintf "%sstruct%s%s%send%s" b "\n"
               (vlist (semi_after str_item) (shi ind 2) (tab (shi ind 2)) sil
                  "")
               ("\n" ^ tab ind) k)
  | z ->
      fun curr next ind b k -> next ind b z k ]
;

value module_expr_apply =
  extfun Extfun.empty with
  [ <:module_expr< $x$ $y$ >> as z ->
      fun curr next ind b k ->
        let unfold =
          fun
          [ <:module_expr< $x$ $y$ >> -> Some (x, "", y)
          | e -> None ]
        in
        left_operator ind 2 unfold next b z k
  | z ->
      fun curr next ind b k -> next ind b z k ]
;

value module_expr_dot =
  extfun Extfun.empty with
  [ <:module_expr< $x$ . $y$ >> ->
      fun curr next ind b k -> curr ind (curr ind b x ".") y k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value module_expr_simple =
  extfun Extfun.empty with
  [ <:module_expr< $uid:s$ >> ->
      fun curr next ind b k -> sprintf "%s%s%s" b s k
  | <:module_expr< ($me$ : $mt$) >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%s(%s : %s)%s" b (module_expr ind "" me "")
               (module_type ind "" mt "") k)
          (fun () ->
             let s1 = module_expr (shi ind 1) (sprintf "%s(" b) me " :" in
             let s2 =
               module_type (shi ind 1) (tab (shi ind 1)) mt (sprintf ")%s" k)
             in
             sprintf "%s\n%s" s1 s2)
  | <:module_expr< struct $list:_$ end >> as z ->
      fun curr next ind b k ->
        module_expr (shi ind 1) (sprintf "%s(" b) z (sprintf ")%s" k)
  | z ->
      fun curr next ind b k -> not_impl "module_expr" ind b z k ]
;

value with_constraint ind b wc k =
  match wc with
  [ <:with_constr< type $sl$ $list:tpl$ = $t$ >> ->
      let b =
        let k = hlist type_var ind "" tpl " = " in
        mod_ident ind (sprintf "%swith type " b) sl k
      in
      ctyp ind b t k
  | <:with_constr< module $sl$ = $me$ >> ->
      module_expr ind (mod_ident ind (sprintf "%swith module " b) sl " = ")
        me k ]
;

value module_type_top =
  extfun Extfun.empty with
  [ <:module_type< functor ($s$ : $mt1$) -> $mt2$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%sfunctor (%s: %s) -> %s%s" b s
               (module_type ind "" mt1 "") (module_type ind "" mt2 "") k)
          (fun () ->
             let s1 =
               horiz_vertic
                 (fun () ->
                    sprintf "%sfunctor (%s: %s) ->" b s
                      (module_type ind "" mt1 ""))
                 (fun () -> not_impl "functor vertic" ind b 0 "")
             in
             let s2 = module_type (shi ind 2) (tab (shi ind 2)) mt2 k in
             sprintf "%s\n%s" s1 s2)
  | <:module_type< sig $list:sil$ end >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%ssig%s%s%send%s" b " "
               (hlist (semi_after sig_item) ind "" sil "")
               " " k)
          (fun () ->
             sprintf "%ssig%s%s%send%s" b "\n"
               (vlist (semi_after sig_item) (shi ind 2) (tab (shi ind 2)) sil
                  "")
               ("\n" ^ tab ind) k)
  | <:module_type< $mt$ with $list:wcl$ >> ->
      fun curr next ind b k ->
        horiz_vertic
          (fun () ->
             sprintf "%s%s %s%s" b (module_type ind "" mt "")
               (hlist with_constraint ind "" wcl "") k)
          (fun () -> not_impl "module type with vertic" ind b wcl k)
  | z ->
      fun curr next ind b k -> next ind b z k ]
;

value module_type_dot =
  extfun Extfun.empty with
  [ <:module_type< $x$ . $y$ >> ->
      fun curr next ind b k -> curr ind (curr ind b x ".") y k
  | z -> fun curr next ind b k -> next ind b z k ]
;

value module_type_simple =
  extfun Extfun.empty with
  [ <:module_type< $uid:s$ >> ->
      fun curr next ind b k -> sprintf "%s%s%s" b s k
  | z -> fun curr next ind b k -> not_impl "module_type" ind b z k ]
;

(* initialization or re-initialization of predefined printers *)

pr_expr.pr_levels :=
  [{pr_label = "top"; pr_rules = expr_top};
   {pr_label = "ass"; pr_rules = expr_assign};
   {pr_label = "bar"; pr_rules = expr_or};
   {pr_label = "amp"; pr_rules = expr_and};
   {pr_label = "less"; pr_rules = expr_less};
   {pr_label = "concat"; pr_rules = expr_concat};
   {pr_label = "add"; pr_rules = expr_add};
   {pr_label = "mul"; pr_rules = expr_mul};
   {pr_label = "pow"; pr_rules = expr_pow};
   {pr_label = "unary"; pr_rules = expr_unary_minus};
   {pr_label = "apply"; pr_rules = expr_apply};
   {pr_label = "dot"; pr_rules = expr_dot};
   {pr_label = "simple"; pr_rules = expr_simple}]
;

pr_patt.pr_levels :=
  [{pr_label = "top"; pr_rules = patt_top};
   {pr_label = "range"; pr_rules = patt_range};
   {pr_label = "apply"; pr_rules = patt_apply};
   {pr_label = "dot"; pr_rules = patt_dot};
   {pr_label = "simple"; pr_rules = patt_simple}]
;

pr_ctyp.pr_levels :=
  [{pr_label = "top"; pr_rules = ctyp_top};
   {pr_label = "arrow"; pr_rules = ctyp_arrow};
   {pr_label = "apply"; pr_rules = ctyp_apply};
   {pr_label = "dot"; pr_rules = ctyp_dot};
   {pr_label = "simple"; pr_rules = ctyp_simple}]
;

pr_str_item.pr_levels := [{pr_label = "top"; pr_rules = str_item_top}];
pr_sig_item.pr_levels := [{pr_label = "top"; pr_rules = sig_item_top}];

pr_module_expr.pr_levels :=
  [{pr_label = "top"; pr_rules = module_expr_top};
   {pr_label = "apply"; pr_rules = module_expr_apply};
   {pr_label = "dot"; pr_rules = module_expr_dot};
   {pr_label = "simple"; pr_rules = module_expr_simple}]
;

pr_module_type.pr_levels :=
  [{pr_label = "top"; pr_rules = module_type_top};
   {pr_label = "dot"; pr_rules = module_type_dot};
   {pr_label = "simple"; pr_rules = module_type_simple}]
;

(* main part *)

value sep = ref None;

value output_string_eval oc s =
  loop 0 where rec loop i =
    if i == String.length s then ()
    else if i == String.length s - 1 then output_char oc s.[i]
    else
      match (s.[i], s.[i + 1]) with
      [ ('\\', 'n') -> do { output_char oc '\n'; loop (i + 2) }
      | (c, _) -> do { output_char oc c; loop (i + 1) } ]
;

value input_source src bp len =
  let len = min (max 0 len) (String.length src) in
  String.sub src bp len
;

value copy_source src oc first bp ep =
  match sep.val with
  [ Some str ->
      if first then ()
      else if ep == String.length src then output_string oc "\n"
      else output_string_eval oc str
  | None ->
      let s = input_source src bp (ep - bp) in
(*
Masked part of code because the 'comment' below does not work for
stdlib/arg.ml in ocaml sources, resulting a printing of half a comment.
Another solution has to be found.
      let s =
        if first then s
        else
          (* generally, what is before the first newline belongs to the
             previous phrase and should have been treated (included, perhaps)
             previously *)
          try
            let i = String.index s '\n' in
            String.sub s i (String.length s - i)
          with
          [ Not_found -> s ]
      in
*)
      output_string oc s ]
;

value copy_to_end src oc first bp =
  let ilen = String.length src in
  if bp < ilen then copy_source src oc first bp ilen
  else output_string oc "\n"
;

module Buff =
  struct
    value buff = ref (String.create 80);
    value store len x = do {
      if len >= String.length buff.val then
        buff.val := buff.val ^ String.create (String.length buff.val)
      else ();
      buff.val.[len] := x;
      succ len
    };
    value mstore len s =
      add_rec len 0 where rec add_rec len i =
        if i == String.length s then len
        else add_rec (store len s.[i]) (succ i)
    ;
    value get len = String.sub buff.val 0 len;
  end
;

value apply_printer f ast = do {
  if Pcaml.input_file.val = "-" then sep.val := Some "\n"
  else do {
    let ic = open_in_bin Pcaml.input_file.val in
    let src =
      loop 0 where rec loop len =
        match try Some (input_char ic) with [ End_of_file -> None ] with
        [ Some c -> loop (Buff.store len c)
        | None -> Buff.get len ]
    in
    Prtools.source.val := src;
    close_in ic
  };
  let oc = stdout in
  let (first, last_pos) =
    List.fold_left
      (fun (first, last_pos) (si, loc) -> do {
         let bp = Stdpp.first_pos loc in
         let ep = Stdpp.last_pos loc in
         copy_source Prtools.source.val oc first last_pos bp;
         flush oc;
         output_string oc (f {ind = 0} "" si ";");
         (False, ep)
       })
      (True, 0) ast
  in
  copy_to_end Prtools.source.val oc first last_pos;
  flush oc
};

Pcaml.print_interf.val := apply_printer sig_item;
Pcaml.print_implem.val := apply_printer str_item;

value is_uppercase c = Char.uppercase c = c;

value set_flags s =
  loop 0 where rec loop i =
    if i = String.length s then ()
    else do {
      match s.[i] with
      [ 'A' | 'a' -> do {
          let v = is_uppercase s.[i] in
          flag_expand_declare.val := v;
          flag_horiz_let_in.val := v;
          flag_sequ_begin_at_eol.val := v;
        }
      | 'D' | 'd' -> flag_expand_declare.val := is_uppercase s.[i]
      | 'L' | 'l' -> flag_horiz_let_in.val := is_uppercase s.[i]
      | 'S' | 's' -> flag_sequ_begin_at_eol.val := is_uppercase s.[i]
      | c -> failwith ("bad flag " ^ String.make 1 c) ];
      loop (i + 1)
    }
;

value default_flag () =
  let flag_on b t f = if b then t else "" in 
  let flag_off b t f = if b then "" else f in
  let on_off flag =
    sprintf "%s%s%s"
      (flag flag_expand_declare.val "D" "d")
      (flag flag_horiz_let_in.val "L" "l")
      (flag flag_sequ_begin_at_eol.val "S" "s")
  in
  let on = on_off flag_on in
  let off = on_off flag_off in
  if String.length on < String.length off then sprintf "a%s" on
  else sprintf "A%s" off
;

value set_wflags s =
  loop 0 where rec loop i =
    if i = String.length s then ()
    else do {
      match s.[i] with
      [ 'A' | 'a' -> do {
          let v = is_uppercase s.[i] in
          flag_where_after_in.val := v;
          flag_where_after_let_eq.val := v;
          flag_where_after_match.val := v;
          flag_where_after_field_eq.val := v;
          flag_where_in_sequences.val := v;
          flag_where_after_then.val := v;
          flag_where_after_value_eq.val := v;
          flag_where_after_arrow.val := v;
        }
      | 'I' | 'i' -> flag_where_after_in.val := is_uppercase s.[i]
      | 'L' | 'l' -> flag_where_after_let_eq.val := is_uppercase s.[i]
      | 'M' | 'm' -> flag_where_after_match.val := is_uppercase s.[i]
      | 'P' | 'p' -> flag_where_after_lparen.val := is_uppercase s.[i]
      | 'R' | 'r' -> flag_where_after_field_eq.val := is_uppercase s.[i]
      | 'S' | 's' -> flag_where_in_sequences.val := is_uppercase s.[i]
      | 'T' | 't' -> flag_where_after_then.val := is_uppercase s.[i]
      | 'V' | 'v' -> flag_where_after_value_eq.val := is_uppercase s.[i]
      | 'W' | 'w' -> flag_where_after_arrow.val := is_uppercase s.[i]
      | c -> failwith ("bad wflag " ^ String.make 1 c) ];
      loop (i + 1)
    }
;

value default_wflag () =
  let flag_on b t f = if b then t else "" in 
  let flag_off b t f = if b then "" else f in
  let on_off flag =
    sprintf "%s%s%s%s%s%s%s%s%s"
      (flag flag_where_after_in.val "I" "i")
      (flag flag_where_after_let_eq.val "L" "l")
      (flag flag_where_after_match.val "M" "m")
      (flag flag_where_after_lparen.val "P" "p")
      (flag flag_where_after_field_eq.val "R" "r")
      (flag flag_where_in_sequences.val "S" "s")
      (flag flag_where_after_then.val "T" "t")
      (flag flag_where_after_value_eq.val "V" "v")
      (flag flag_where_after_arrow.val "W" "w")
  in
  let on = on_off flag_on in
  let off = on_off flag_off in
  if String.length on < String.length off then sprintf "a%s" on
  else sprintf "A%s" off
;

Pcaml.add_option "-flag" (Arg.String set_flags)
  ("<str> Change pretty printing behaviour according to <flags>:
       A/a enable/disable all flags
       D/d enable/disable allowing expanding 'declare'
       L/l enable/disable allowing printing 'let..in' horizontally
       S/s enable/disable printing sequences beginners at end of lines
       default setting is \"" ^ default_flag () ^ "\".");

Pcaml.add_option "-wflag" (Arg.String set_wflags)
  ("<str> Change displaying 'where' statements instead of 'let':
       A/a enable/disable all flags
       I/i enable/disable 'where' after 'in'
       L/l enable/disable 'where' after 'let..='
       M/m enable/disable 'where' after 'match' and 'try'
       P/p enable/disable 'where' after left parenthesis
       R/r enable/disable 'where' after 'record_field..='
       S/s enable/disable 'where' in sequences
       T/t enable/disable 'where' after 'then' or 'else'
       V/v enable/disable 'where' after 'value..='
       W/w enable/disable 'where' after '->'
       default setting is \"" ^ default_wflag () ^ "\".");

Pcaml.add_option "-l" (Arg.Int (fun x -> Pretty.line_length.val := x))
  ("<length> Maximum line length for pretty printing (default " ^
     string_of_int Pretty.line_length.val ^ ")");

Pcaml.add_option "-sep" (Arg.String (fun x -> sep.val := Some x))
  "<string> Use this string between phrases instead of reading source.";
