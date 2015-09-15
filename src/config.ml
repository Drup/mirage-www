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

let keys = Key.[ hidden host_key ; hidden redirect_key ]


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
    (http @-> console @-> kv_ro @-> kv_ro @-> clock @-> job)

let https =
  let libraries = [ "tls"; "tls.mirage"; "mirage-http" ] in
  let packages = ["tls"; "tls"; "mirage-http"] in
  foreign ~libraries ~packages  ~keys "Dispatch_tls.Make"
    ~dependencies:[hidden nocrypto]
    (stackv4 @-> kv_ro @-> console @-> kv_ro @-> kv_ro @-> clock @-> job)


let dispatch = if_impl (Key.value tls_key)
    (** With tls *)
    (https $ stack $ secrets)

    (** Without tls *)
    (http  $ http_server (conduit_direct stack))

let libraries = [ "cow.syntax"; "cowabloga"; "rrd" ]
let packages  = [ "cow"; "cowabloga"; "xapi-rrd"; "c3" ]

let () =
  let tracing = None in
  (* let tracing = mprof_trace ~size:10000 () in *)
  register ?tracing ~libraries ~packages "www" [
    dispatch $ default_console $ filesfs $ tmplfs $ default_clock
  ]
