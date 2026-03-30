open Ppxlib
open Ppxlib_jane
module Map = Map.Make (String)

let override = ref None

let () =
  Driver.add_arg
    "-amd64"
    (Arg.Unit (fun () -> override := Some "amd64"))
    ~doc:" override the architecture to amd64 (for testing)";
  Driver.add_arg
    "-arm64"
    (Arg.Unit (fun () -> override := Some "arm64"))
    ~doc:" override the architecture to arm64 (for testing)"
;;

let arch () =
  match !override with
  | Some s -> s
  | None -> Ocaml_common.Config.config_var "architecture" |> Option.value ~default:""
;;

let arch_symbol expr =
  match Shim.Expression_desc.of_parsetree expr.pexp_desc ~loc:expr.pexp_loc with
  | Pexp_ident { txt = Lident arch; _ } -> Some (arch, None)
  | Pexp_tuple
      [ (None, { pexp_desc = Pexp_ident { txt = Lident arch; _ }; _ })
      ; (None, { pexp_desc = Pexp_constant (Pconst_string (symbol, _, _)); _ })
      ] -> Some (arch, Some symbol)
  | _ -> None
;;

let rec arch_symbol_sequence expr =
  match arch_symbol expr with
  | Some arch -> [ arch ]
  | None ->
    (match expr.pexp_desc with
     | Pexp_apply (func, args) ->
       let func_tuples = arch_symbol_sequence func in
       let arg_tuples = List.concat_map (fun (_, arg) -> arch_symbol_sequence arg) args in
       func_tuples @ arg_tuples
     | _ -> [])
;;

(** [builtin_payload] takes the entry [E] from [@@builtin E] and parses it into a map from
    architectures to optional symbols. *)
let builtin_payload payload =
  match payload with
  | PStr items ->
    List.concat_map
      (fun item ->
        match item.pstr_desc with
        | Pstr_eval (expr, _) -> arch_symbol_sequence expr
        | _ -> [])
      items
    |> Map.of_list
  | _ -> Map.empty
;;

let filter_attributes attrs =
  let sym = ref None in
  let filter attr =
    if String.equal attr.attr_name.txt "builtin"
    then (
      let map = builtin_payload attr.attr_payload in
      if Map.is_empty map
      then Some attr
      else (
        match Map.find_opt (arch ()) map with
        | Some replacement ->
          sym := replacement;
          Some { attr with attr_payload = PStr [] }
        | None ->
          Attribute.mark_as_handled_manually attr;
          None))
    else Some attr
  in
  let attrs = List.filter_map filter attrs in
  attrs, !sym
;;

let replace_symbol prims sym =
  match sym, prims with
  | Some sym, [ _ ] -> [ sym ]
  | Some sym, [ bytecode; _ ] -> [ bytecode; sym ]
  | _ -> prims
;;

let mapper =
  object
    inherit Ast_traverse.map as super

    method! value_description desc =
      let desc =
        if List.length desc.pval_prim = 0
        then desc
        else (
          let pval_attributes, sym = filter_attributes desc.pval_attributes in
          let pval_prim = replace_symbol desc.pval_prim sym in
          { desc with pval_attributes; pval_prim })
      in
      super#value_description desc
  end
;;

let () =
  Driver.register_transformation "builtin" ~impl:mapper#structure ~intf:mapper#signature
;;
