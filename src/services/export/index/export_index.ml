(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

type kind =
  | Default
  | Named
  | NamedType
  | Namespace
[@@deriving show, ord]

type source =
  | Global
  | Builtin of string  (** [Builtin "foo"] refers to a `declare module "foo"` lib *)
  | File_key of File_key.t
[@@deriving show]

(** Custom ordering where the "kind" (LibFile vs SourceFile vs JsonFile, etc) does
    not matter, and we compare filenames without extensions, so that something like
    [Foo.example.js] sorts _after_ [Foo.js] even though [e] comes before [j]; the
    extension is less important than the rest of the basename and we should suggest
    [import ... from 'Foo'] before [import ... from 'Foo.example']. *)
let compare_file_key a b =
  let open File_key in
  let a = to_string a in
  let b = to_string b in
  let k = String.compare (Filename.chop_extension a) (Filename.chop_extension b) in
  if k <> 0 then
    k
  else
    String.compare a b

(** Custom ordering where globals come first, followed by [declare module],
    followed by source files.

    Exports are sorted by both source and kind. After sorting by kind (defaults
    before named before namespace), we then want globals first, followed by
    declared modules (builtins). In this way, if there is a module named `Map`
    with a default export, it'll be suggested before the builtin `Map`, but
    some other module with a named `Map` export will be suggested after. This
    is so that named exports from random modules don't shadow common globals,
    but you can still shadow the builtins with an entire module (e.g. a Promise
    polyfill defined by the `Promise` module).

    TODO: this is a very coarse ranking. We could do much better. For example, we
    could track how commonly used each export is. For example, the `Promise` global
    is probably far more common than any source file exporting the same name. *)
let compare_source a b =
  match (a, b) with
  (* globals first *)
  | (Global, Global) -> 0
  | (Global, _) -> -1
  | (_, Global) -> 1
  (* builtins second *)
  | (Builtin a, Builtin b) -> String.compare a b
  | (Builtin _, _) -> -1
  | (_, Builtin _) -> 1
  (* user modules last *)
  | (File_key a, File_key b) -> compare_file_key a b

type export = source * kind [@@deriving show]

(** Order by kind and then by source.

  1. Default exports from declared modules (builtins)
  2. Default exports from user modules
  3. Named exports from globals (e.g. `declare class Image`)
  4. Named exports from declared modules
  5. Named exports from user modules
  6. Same for types
  7. Namespaces of declared modules
  8. Namespaces of user modules
 *)
let compare_export (a_source, a_kind) (b_source, b_kind) =
  let k = compare_kind a_kind b_kind in
  if k = 0 then
    compare_source a_source b_source
  else
    k

module ExportSet = struct
  include Flow_set.Make (struct
    type t = export

    let compare = compare_export
  end)

  let pp fmt x =
    Format.fprintf fmt "@[<hv 2>{";
    let elements = elements x in
    (match elements with
    | [] -> ()
    | _ -> Format.fprintf fmt " ");
    ignore
      (List.fold_left
         (fun sep elt ->
           if sep then Format.fprintf fmt ";@ ";
           pp_export fmt elt;
           true)
         false
         elements
      );
    (match elements with
    | [] -> ()
    | _ -> Format.fprintf fmt " ");
    Format.fprintf fmt "}@]"

  let show x = Format.asprintf "%a" pp x
end

type t = ExportSet.t SMap.t [@@deriving show]

let empty = SMap.empty

let add : string -> source -> kind -> t -> t =
  let add_file file_key kind = function
    | None -> Some (ExportSet.singleton (file_key, kind))
    | Some exports -> Some (ExportSet.add (file_key, kind) exports)
  in
  (fun name file_key kind t -> SMap.update name (add_file file_key kind) t)

let merge x y = SMap.union ~combine:(fun _key a b -> Some (ExportSet.union a b)) x y

let fold_names ~f ~init t = SMap.fold (fun name exports acc -> f acc name exports) t init

let fold ~f ~init t =
  fold_names
    ~f:(fun acc name exports -> ExportSet.fold (fun export acc -> f acc name export) exports acc)
    ~init
    t

let map ~f t = SMap.map (ExportSet.map f) t

let subtract old_t t =
  let (t, dead_names) =
    SMap.fold
      (fun name files_to_remove (t, dead_names) ->
        match SMap.find_opt name t with
        | Some files ->
          let updated = ExportSet.diff files files_to_remove in
          if ExportSet.is_empty updated then
            (SMap.remove name t, name :: dead_names)
          else
            (SMap.add name updated t, dead_names)
        | None -> (t, dead_names))
      old_t
      (t, [])
  in
  (t, dead_names)

(** [find name t] returns all of the [(file_key, kind)] tuples that export [name] *)
let find name (t : t) =
  match SMap.find_opt name t with
  | Some exports -> exports
  | None -> ExportSet.empty

let find_seq name t =
  match SMap.find_opt name t with
  | Some t -> ExportSet.to_seq t
  | None -> Seq.empty

(** [keys t] returns all of the exported names from every file in [t] *)
let keys t = SMap.keys t

let kind_is_value = function
  | Default
  | Named
  | Namespace ->
    true
  | NamedType -> false

let kind_is_type = function
  | Default
  | Named
  | Namespace ->
    false
  | NamedType -> true
