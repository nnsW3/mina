open Core_kernel

[@@@warning "-4"]

type ('a, 'bool) t = Some of 'a | None | Maybe of 'bool * 'a
[@@deriving sexp, compare, yojson, hash, equal]

let some a = Some a

let none = None

let maybe b x = Maybe (b, x)

let to_option : ('a, bool) t -> 'a option = function
  | Some x ->
      Some x
  | Maybe (true, x) ->
      Some x
  | Maybe (false, _x) ->
      None
  | None ->
      None

let to_option_unsafe : ('a, 'bool) t -> 'a option = function
  | Some x ->
      Some x
  | Maybe (_, x) ->
      Some x
  | None ->
      None

let value_exn = function
  | Some x ->
      x
  | Maybe (_, x) ->
      x
  | None ->
      invalid_arg "Opt.value_exn"

let of_option (t : 'a option) : ('a, 'bool) t =
  match t with None -> None | Some x -> Some x

let lift ?on_maybe ~none f = function
  | None ->
      none
  | Some v ->
      f v
  | Maybe (b, v) -> (
      match on_maybe with None -> f v | Some g -> g b v )

module Flag = struct
  type t = Yes | No | Maybe [@@deriving sexp, compare, yojson, hash, equal]

  let ( ||| ) x y =
    match (x, y) with
    | Yes, _ | _, Yes ->
        Yes
    | Maybe, _ | _, Maybe ->
        Maybe
    | No, No ->
        No
end

let map t ~f =
  match t with
  | None ->
      None
  | Some x ->
      Some (f x)
  | Maybe (b, x) ->
      Maybe (b, f x)

open Snarky_backendless

let some_typ (type a a_var f bool_var) (t : (a_var, a, f) Typ.t) :
    ((a_var, bool_var) t, a option, f) Typ.t =
  Typ.transport t ~there:(fun x -> Option.value_exn x) ~back:Option.return
  |> Typ.transport_var
       ~there:(function
         | Some x ->
             x
         | Maybe _ | None ->
             failwith "Opt.some_typ: expected Some" )
       ~back:(fun x -> Some x)

let none_typ (type a a_var f bool) () : ((a_var, bool) t, a option, f) Typ.t =
  Typ.transport (Typ.unit ())
    ~there:(fun _ -> ())
    ~back:(fun () : _ Option.t -> None)
  |> Typ.transport_var
       ~there:(function
         | None ->
             ()
         | Maybe _ | Some _ ->
             failwith "Opt.none_typ: expected None" )
       ~back:(fun () : _ t -> None)

let maybe_typ (type a a_var bool_var f)
    (bool_typ : (bool_var, bool, f) Snarky_backendless.Typ.t) ~(dummy : a)
    (a_typ : (a_var, a, f) Typ.t) : ((a_var, bool_var) t, a option, f) Typ.t =
  Typ.transport
    (Typ.tuple2 bool_typ a_typ)
    ~there:(fun (t : a option) ->
      match t with None -> (false, dummy) | Some x -> (true, x) )
    ~back:(fun (b, x) -> if b then Some x else None)
  |> Typ.transport_var
       ~there:(fun (t : (a_var, _) t) ->
         match t with
         | Maybe (b, x) ->
             (b, x)
         | None | Some _ ->
             failwith "Opt.maybe_typ: expected Maybe" )
       ~back:(fun (b, x) -> Maybe (b, x))

let constant_layout_typ (type a a_var f) (bool_typ : _ Typ.t) ~true_ ~false_
    (flag : Flag.t) (a_typ : (a_var, a, f) Typ.t) ~(dummy : a)
    ~(dummy_var : a_var) =
  let (Typ bool_typ) = bool_typ in
  let bool_typ : _ Typ.t =
    let check =
      (* No need to boolean constrain in the No or Yes case *)
      match flag with
      | No | Yes ->
          fun _ -> Checked_runner.Simple.return ()
      | Maybe ->
          bool_typ.check
    in
    Typ { bool_typ with check }
  in
  Typ.transport
    (Typ.tuple2 bool_typ a_typ)
    ~there:(fun (t : a option) ->
      match t with None -> (false, dummy) | Some x -> (true, x) )
    ~back:(fun (b, x) -> if b then Some x else None)
  |> Typ.transport_var
       ~there:(fun (t : (a_var, _) t) ->
         match t with
         | Maybe (b, x) ->
             (b, x)
         | None ->
             (false_, dummy_var)
         | Some x ->
             (true_, x) )
       ~back:(fun (b, x) ->
         match flag with No -> None | Yes -> Some x | Maybe -> Maybe (b, x) )

let typ (type a a_var f) bool_typ (flag : Flag.t) (a_typ : (a_var, a, f) Typ.t)
    ~(dummy : a) =
  match flag with
  | Yes ->
      some_typ a_typ
  | No ->
      none_typ ()
  | Maybe ->
      maybe_typ bool_typ ~dummy a_typ

module Early_stop_sequence = struct
  (* A sequence that should be considered to have stopped at
     the first No flag *)
  (* TODO: The documentation above makes it sound like the type below is too
     generic: we're not guaranteed to have flags in there *)
  type nonrec ('a, 'bool) t = ('a, 'bool) t list

  let fold (type a bool acc res)
      (if_res : bool -> then_:res -> else_:res -> res) (t : (a, bool) t)
      ~(init : acc) ~(f : acc -> a -> acc) ~(finish : acc -> res) =
    let rec go acc = function
      | [] ->
          finish acc
      | None :: xs ->
          go acc xs
      | Some x :: xs ->
          go (f acc x) xs
      | Maybe (b, x) :: xs ->
          (* Computing this first makes mutation in f OK. *)
          let stop_res = finish acc in
          let continue_res = go (f acc x) xs in
          if_res b ~then_:continue_res ~else_:stop_res
    in
    go init t
end