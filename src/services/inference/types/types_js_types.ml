(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

type parse_artifacts =
  | Parse_artifacts of {
      docblock: Docblock.t;
      docblock_errors: Docblock_parser.docblock_error list;
      ast: (Loc.t, Loc.t) Flow_ast.Program.t;
      file_sig: File_sig.With_Loc.t;
      tolerable_errors: File_sig.With_Loc.tolerable_error list;
      parse_errors: (Loc.t * Parse_error.t) list;
    }

type typecheck_artifacts =
  | Typecheck_artifacts of {
      cx: Context.t;
      typed_ast: (ALoc.t, ALoc.t * Type.t) Flow_ast.Program.t;
      obj_to_obj_map: Type.Properties.Set.t Loc_collections.LocMap.t;
    }

type file_artifacts = parse_artifacts * typecheck_artifacts
