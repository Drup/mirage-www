(*
 * Copyright (c) 2015 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Mirage

let split c s =
  let rec aux c s ri acc =
    (* half-closed intervals. [ri] is the open end, the right-fencepost.
       [li] is the closed end, the left-fencepost. either [li] is
       + negative (outside [s]), or
       + equal to [ri] ([c] not found in remainder of [s]) ->
         take everything from [ s[0], s[ri] )
       + else inside [s], thus an instance of the separator ->
         accumulate from the separator to [ri]: [ s[li+1], s[ri] )
         and move [ri] inwards to the discovered separator [li]
    *)
    let li = try String.rindex_from s (ri-1) c with Not_found -> -1 in
    if li < 0 || li == ri then (String.sub s 0 ri) :: acc
    else begin
      let len = ri-1 - li in
      let rs = String.sub s (li+1) len in
      aux c s li (rs :: acc)
    end
  in
  aux c s (String.length s) []

let ips_of_env x = split ':' x |> List.map Ipaddr.V4.of_string_exn
let bool_of_env = function "1" | "true" | "yes" -> true | _ -> false
let socket_of_env = function "socket" -> `Socket | _ -> `Direct
let fat_of_env = function "fat" -> `Fat | "archive" -> `Archive | _ -> `Crunch
let opt_string_of_env x = Some x
let string_of_env x = x

let err fmt =
  Printf.ksprintf (fun str ->
      Printf.eprintf ("\027[31m[ERROR]\027[m     %s\n") str;
      exit 1
    ) fmt

let env_info fmt = Printf.printf ("\027[33mENV\027[m         " ^^ fmt ^^ "\n%!")

let get_env name fn =
  let res = Sys.getenv name in
  env_info "%s => %s" name res;
  fn (String.lowercase res)

let get_exn name fn =
  try get_env name fn
  with Not_found ->
    err "%s is not set." name

let get ~default name fn =
  try get_env name fn
  with Not_found ->
    env_info "%s => not set." name;
    default

let tls_key =
  let doc = Key.Doc.create
      ~doc:"Enable serving the website over https." ["tls"]
  in
  Key.create ~doc ~default:false ~stage:`Configure "tls" Key.Desc.bool

let pr_key =
  let doc = Key.Doc.create
      ~doc:"Configuration for running inside a travis PR." ["pr"]
  in
  Key.create ~doc ~default:false ~stage:`Configure "pr" Key.Desc.bool


let host_key =
  let doc = Key.Doc.create ~doc:"Hostname of the unikernel." ["host"] in
  Key.create ~doc ~default:"localhost" "host" Key.Desc.string

let redirect_key =
  let doc = Key.Doc.create ~doc:"Where to redirect to." ["redirect"] in
  Key.create ~doc ~default:None "redirect" Key.Desc.(option string)

let keys = Key.[ hide host_key ; hide redirect_key ]


let image = get "XENIMG" ~default:"www" string_of_env

let filesfs = generic_kv_ro ~group:"file" "../files"
let tmplfs = generic_kv_ro ~group:"tmpl" "../tmpl"

(* If we are running inside a PR in Travis CI,
   we don't try to get the server certificates. *)
let secrets =
  if_impl (Key.value pr_key)
    (crunch "../src")
    (generic_kv_ro ~group:"secret" "../tls")

let stack = generic_stackv4 default_console tap0


let http =
  foreign ~keys "Dispatch.Make"
    (console @-> kv_ro @-> kv_ro @-> http @-> clock @-> job)

let https =
  let libraries = [ "tls"; "tls.mirage"; "mirage-http" ] in
  let packages = ["tls"; "tls"; "mirage-http"] in
  foreign ~libraries ~packages  ~keys "Dispatch_tls.Make"
    ~dependencies:[hide nocrypto]
    (console @-> kv_ro @-> kv_ro @-> stackv4 @-> kv_ro @-> clock @-> job)


let dispatch = if_impl (Key.value tls_key)
    (** With tls *)
    begin
      let clock = default_clock in
      https $ default_console $ filesfs $ tmplfs $ stack $ secrets $ clock
    end
    (** Without tls *)
    begin
      let server = http_server (conduit_direct stack) in
      let clock = default_clock in
      http  $ default_console $ filesfs $ tmplfs $ server $ clock
    end

let libraries = [ "cow.syntax"; "cowabloga"; "rrd" ]
let packages  = [ "cow"; "cowabloga"; "xapi-rrd"; "c3" ]

let () =
  let tracing = None in
  (* let tracing = mprof_trace ~size:10000 () in *)
  register ?tracing ~libraries ~packages image [ dispatch ]
