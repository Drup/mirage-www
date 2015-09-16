
For the last two month, I have been at OCamllabs for « holidays » with the grand task
of « fixing the mirage tool » *cough*.

I'm happy to present [Functoria](https://github.com/Drup/Functoria), a library to create arbitrary mirage-like DSLs. Functoria is independent from Mirage and will replace all the core engine that was bolted on the mirage tool until now.

The bad news is that it's going to break some (little) things, the good news is that it will be much more simple to use and much more flexible.
And it produces pretty pictures.

Let's start by the unpleasant part: the things that breaks (and how to migrate).

## Breaking the law

### Command line

The options `--unix` and `--xen` are not available anymore.
They must be replaced respectively by `-t unix` and `-t xen`.
This option was available before so this is retro-compatible.

The config file must be passed with the `-f` option (instead of being just
an argument).

### Misc functions

The `get_mode` function is still available, but deprecated. You should use
[Keys](#Keeperofthesevenkeys) instead. And in particular, `Key.target`.

The functions `add_to_ocamlfind_libraries` and `add_to_opam_packages` are deprecated. Both the `foreign` and the `register` functions now possess the `~libraries` and `~packages` arguments to specify libraries dependencies.
I encourage unikernel writers to be precise about their dependencies: Dependencies that are only for a foreign module and not for the whole module should be given to the `foreign` function.

### Entropy

If you were using `tls` before without the conduit combinator, you will be
greeted during configuration by a message like this:

```
The "tls" library is loaded but entropy is not enabled!
Please enable the entropy by adding a dependency to the nocrypto device.
You can do so with the ~dependency argument of Mirage.foreign.
```

Data dependencies (such as entropy initialization) are now explicit.
In order to fix this, you need to declare the dependency like so:
```
open Mirage

let my_functor =
  let dependencies = [hide nocrypto] in
  foreign ~dependencies "My_Functor" (foo @-> bar)
```

The `My_functor.start` function will also now takes an extra argument for each
dependencies. In the case of nocrypto, this is `()`.

We will see more about data-dependencies in the [related section](#dependencies).

And that's all. We can now move on to the good parts!

## Keeper of the seven keys

A [much][] [reclaimed][] [feature][] is the ability to define so called bootvars.
Bootvars are variables which value would be set either at configure time or at
startup time.

[much]: https://github.com/mirage/mirage/issues/229
[reclaimed]: https://github.com/mirage/mirage/issues/228
[feature]: https://github.com/mirage/mirage/issues/231


A good example is the ip address of the http stack, you want to be able to:

- Set a good default directly in the `config.ml`
- Provide a value at configure time, if you are already aware of deployment conditions.
- Provide a value at startup time, for last minute changes.

All of this is now possible using **keys**. A key is composed of :
- _name_ : The name of the value in the program.
- _description_ : How it should be displayed/serialized.
- _stage_ : Is the key available only at runtime, at configure time or both ?
- _documentation_ : It is not optional so you should really write it.

Let's consider we are building a multilingual unikernel and we want to pass the
default language as a parameter. We will use a simple string, so we can use the
predefined description `Key.Desc.string`. We want to be able to define it both
at configure and run time, so we use the stage `` `Both``. This gives us the following code:

```
let lang_key =
  let doc = Key.Doc.create
      ~doc:"The default language for the unikernel." [ "l" ; "lang" ]
  in
  Key.create ~doc ~stage:`Both ~default:"fr" "language" Key.Desc.string
```

Here, We defined both a long option `--lang` and a short one `-l`. (this is the same format as the one used by [Cmdliner][cmdliner]).
In the unikernel, the value is retrieved with `Bootvar_gen.language ()`.

The option is also documented in the `--help` option for both `mirage config` (at configure time) and `./my_unikernel` (at startup time).

```
       -l VAL, --lang=VAL (absent=fr)
           The default language for the unikernel.
```

[cmdliner]: http://erratique.ch/software/cmdliner

### Keys to the Kingdom

We can actually do much more with keys: we can use them to switch implementation
at configure time. To illustrate, let us take the example of a dynamic storage: We want to choose between a block device and a crunch device with a command line option.
In order to do that, we must first define a boolean key:

```
let fat_key =
  let doc = Key.Doc.create
      ~doc:"Use a fat device if true, crunch otherwise." [ "fat" ]
  in
  Key.create ~doc ~stage:`Configure ~default:false "fat" Key.Desc.bool
```

We can now use the `if_impl` combinator to choose between two devices depending on the value of the key.

```
let dynamic_storage =
  if_impl (Key.value fat_key)
    (kv_ro_of_fs my_fat_device)
    (my_crunch_device)
```

We can now use this device as a normal storage device of type `kv_ro impl`!

It is also possible to compute on keys before giving them to `if_impl`, combining multiple keys in order to compute a value, and so on. The documentation for the API is located in the `Mirage.Key` module and various examples are available in `mirage` and `mirage-skeleton`.

Switching keys opens various possibilities, for example a `generic_stack` combinator is now implemented in mirage that will switch between socket stack, direct stack with dhcp and direct stack with static ip, depending on command line arguments.

## All your functors are belong to us

All these keys and dynamic implementations makes for complicated unikernels. In order to still be able to understand what is going on and how to configure our unikernels, functoria adds a new command: `describe`.

If we go to the directory `console` in [mirage-skeleton](github.com/mirage/mirage-skeleton.git) and type `mirage describe --dot`, we will get the following output.

![A console unikernel](../graphics/dot/console.png "My little unikernel")

As you can see, the actualy

## Data dependencies

## Sharing
