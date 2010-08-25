(* camlp5r *)
(* $Id: main.ml,v 1.14 2010/08/25 11:28:59 deraugla Exp $ *)
(* Copyright (c) INRIA 2007-2010 *)

#load "q_MLast.cmo";

open Printf;
open Versdep;

value string_of_loc fname line bp ep =
  match Sys.os_type with
  [ "MacOS" ->
      sprintf "File \"%s\"; line %d; characters %d to %d\n### " fname line
        bp ep
  | _ ->
      sprintf "File \"%s\", line %d, characters %d-%d:\n" fname line bp ep ]
;

value print_location loc =
  if Pcaml.input_file.val <> "-" then
    let (fname, line, bp, ep) = Ploc.from_file Pcaml.input_file.val loc in
    eprintf "%s" (string_of_loc fname line bp ep)
  else
    let bp = Ploc.first_pos loc in
    let ep = Ploc.last_pos loc in
    eprintf "At location %d-%d\n" bp ep
;

value print_warning loc s = do {
  print_location loc;
  eprintf "Warning: %s\n" s;
  flush stderr
};

value report_error =
  fun
  [ Odyl_main.Error fname msg -> do {
      Format.print_string "Error while loading \"";
      Format.print_string fname;
      Format.print_string "\": ";
      Format.print_string msg
    }
  | exc -> Pcaml.report_error exc ]
;

value report_error_and_exit exc = do {
  Format.set_formatter_out_channel stderr;
  Format.open_vbox 0;
  let exc =
    match exc with
    [ Ploc.Exc loc exc -> do { print_location loc; exc }
    | _ -> exc ]
  in
  report_error exc;
  Format.close_box ();
  Format.print_newline ();
  exit 2
};

Pcaml.add_directive "load"
  (fun
   [ Some <:expr< $str:s$ >> -> Odyl_main.loadfile s
   | Some _ | None -> raise Not_found ]);

Pcaml.add_directive "directory"
  (fun
   [ Some <:expr< $str:s$ >> -> Odyl_main.directory s
   | Some _ | None -> raise Not_found ]);

value rec parse_file pa getdir useast = do {
  let name = Pcaml.input_file.val in
  Pcaml.warning.val := print_warning;
  let ic = if name = "-" then stdin else open_in_bin name in
  let cs = Stream.of_channel ic in
  let clear () = if name = "-" then () else close_in ic in
  let phr =
    try
      loop () where rec loop () =
        let (pl, stopped_at_directive) = pa cs in
        if stopped_at_directive then do {
          let lexing_info =
            (Plexing.line_nb.val.val, Plexing.bol_pos.val.val)
          in
          let pl =
            let rpl = List.rev pl in
            match getdir rpl with
            [ Some x ->
                match x with
                [ (loc1, "use", Some <:expr< $str:s$ >>) ->
                    List.rev_append rpl
                      [(useast loc1 s (use_file pa getdir useast s), loc1)]
                | (loc, x, eo) -> do {
                    try
                      let f = Pcaml.find_directive x in
                      f eo
                    with
                    [ Not_found ->
                        Ploc.raise loc (Stream.Error "bad directive") ];
                    pl
                  } ]
            | None -> pl ]
          in
          Plexing.restore_lexing_info.val := Some lexing_info;
          pl @ loop ()
        }
        else pl
    with x -> do { clear (); raise x }
  in
  clear ();
  phr
}
and use_file pa getdir useast s = do {
  let v_input_file = Pcaml.input_file.val in
  Pcaml.input_file.val := s;
  try do {
    let r = parse_file pa getdir useast in
    Pcaml.input_file.val := v_input_file;
    r
  }
  with e -> report_error_and_exit e
};

value process pa pr getdir useast = pr (parse_file pa getdir useast);

value gind =
  fun
  [ [(MLast.SgDir loc n dp, _) :: _] ->
      Some (loc, Pcaml.unvala n, Pcaml.unvala dp)
  | _ -> None ]
;

value gimd =
  fun
  [ [(MLast.StDir loc n dp, _) :: _] ->
      Some (loc, Pcaml.unvala n, Pcaml.unvala dp)
  | _ -> None ]
;

value usesig loc fname ast = MLast.SgUse loc fname ast;
value usestr loc fname ast = MLast.StUse loc fname ast;

value process_intf () =
  process Pcaml.parse_interf.val Pcaml.print_interf.val gind usesig
;
value process_impl () =
  process Pcaml.parse_implem.val Pcaml.print_implem.val gimd usestr
;

type file_kind = [ Intf | Impl ];
value file_kind = ref Intf;
value file_kind_of_name name =
  if Filename.check_suffix name ".mli" then Intf
  else if Filename.check_suffix name ".ml" then Impl
  else raise (Arg.Bad ("don't know what to do with " ^ name))
;

value print_version () = do {
  eprintf "Camlp5 version %s (ocaml %s)\n" Pcaml.version
    Pconfig.ocaml_version;
  flush stderr;
  exit 0
};

value initial_spec_list =
  [("-intf",
    Arg.String
      (fun x -> do { file_kind.val := Intf; Pcaml.input_file.val := x }),
    "<file>  Parse <file> as an interface, whatever its extension.");
   ("-impl",
    Arg.String
      (fun x -> do { file_kind.val := Impl; Pcaml.input_file.val := x }),
    "<file>  Parse <file> as an implementation, whatever its extension.");
   ("-unsafe", Arg.Set Ast2pt.fast,
    "Generate unsafe accesses to array and strings.");
   ("-verbose", Arg.Set Grammar.error_verbose,
    "More verbose in parsing errors.");
   ("-loc", Arg.String (fun x -> Ploc.name.val := x),
    "<name>   Name of the location variable (default: " ^ Ploc.name.val ^
    ")");
   ("-QD", Arg.String (fun x -> Pcaml.quotation_dump_file.val := Some x),
    "<file> Dump quotation expander result in case of syntax error.");
   ("-o", Arg.String (fun x -> Pcaml.output_file.val := Some x),
    "<file> Output on <file> instead of standard output.");
   ("-v", Arg.Unit print_version, "Print Camlp5 version and exit.")]
;

value anon_fun x = do {
  Pcaml.input_file.val := x;
  file_kind.val := file_kind_of_name x
};

value remaining_args =
  let rec loop l i =
    if i == Array.length Sys.argv then l else loop [Sys.argv.(i) :: l] (i + 1)
  in
  List.rev (loop [] (Arg.current.val + 1))
;

value go () = do {
  let ext_spec_list = Pcaml.arg_spec_list () in
  let arg_spec_list = initial_spec_list @ ext_spec_list in
  try
    match Argl.parse arg_spec_list anon_fun remaining_args with
    [ [] -> ()
    | ["-help" :: sl] -> do {
        Argl.usage initial_spec_list ext_spec_list;
        exit 0
      }
    | [s :: sl] -> do {
        eprintf "%s: unknown or misused option\n" s;
        eprintf "Use option -help for usage\n";
        exit 2
      } ]
  with
  [ Arg.Bad s -> do {
      eprintf "Error: %s\n" s;
      eprintf "Use option -help for usage\n";
      flush stderr;
      exit 2
    } ];
  try
    if Pcaml.input_file.val <> "" then
      match file_kind.val with
      [ Intf -> process_intf ()
      | Impl -> process_impl () ]
    else ()
  with exc -> report_error_and_exit exc
};

Odyl_main.name.val := "camlp5";
Odyl_main.go.val := go;
