open Core_kernel
module Bignum_bigint = Snarky_backendless.Backend_extended.Bignum_bigint
module Snark_intf = Snarky_backendless.Snark_intf

let tests_enabled = true

let two_to_4limb = Bignum_bigint.(Common.two_to_3limb * Common.two_to_limb)

(* Affine representation of an elliptic curve point over a foreign field *)
module Affine : sig
  type 'field t

  (* Create foreign field affine point from coordinate pair (x, y) *)
  val of_coordinates :
       'field Foreign_field.Element.Standard.t
       * 'field Foreign_field.Element.Standard.t
    -> 'field t

  (* Create foreign field affine point from coordinate pair of Bignum_bigint.t (x, y) *)
  val of_bignum_bigint_coordinates :
       (module Snark_intf.Run with type field = 'field)
    -> Bignum_bigint.t * Bignum_bigint.t
    -> 'field t

  (* Create foreign field affine point from hex *)
  val of_hex :
    (module Snark_intf.Run with type field = 'field) -> string -> 'field t

  (* Convert foreign field affine point to coordinate pair (x, y) *)
  val to_coordinates :
       'field t
    -> 'field Foreign_field.Element.Standard.t
       * 'field Foreign_field.Element.Standard.t

  (* Convert foreign field affine point to hex *)
  val to_hex_as_prover :
    (module Snark_intf.Run with type field = 'field) -> 'field t -> string

  (* Access x-coordinate of foreign field affine point *)
  val x : 'field t -> 'field Foreign_field.Element.Standard.t

  (* Access y-coordinate of foreign field affine point *)
  val y : 'field t -> 'field Foreign_field.Element.Standard.t

  (* Compare if two foreign field affine points are equal *)
  val equal_as_prover :
       (module Snark_intf.Run with type field = 'field)
    -> 'field t
    -> 'field t
    -> bool

  (* Add copy constraints that two Affine points are equal *)
  val assert_equal :
       (module Snark_intf.Run with type field = 'field)
    -> 'field t
    -> 'field t
    -> unit

  (* Zero point *)
  val zero_as_prover :
    (module Snark_intf.Run with type field = 'field) -> 'field t
end = struct
  type 'field t =
    'field Foreign_field.Element.Standard.t
    * 'field Foreign_field.Element.Standard.t

  let of_coordinates a = a

  let of_bignum_bigint_coordinates (type field)
      (module Circuit : Snark_intf.Run with type field = field)
      (point : Bignum_bigint.t * Bignum_bigint.t) : field t =
    let x, y = point in
    of_coordinates
      ( Foreign_field.Element.Standard.of_bignum_bigint (module Circuit) x
      , Foreign_field.Element.Standard.of_bignum_bigint (module Circuit) y )

  let of_hex (type field)
      (module Circuit : Snark_intf.Run with type field = field) a : field t =
    let a = Common.bignum_bigint_of_hex a in
    let x, y = Common.(bignum_bigint_div_rem a two_to_4limb) in
    let x =
      Foreign_field.Element.Standard.of_bignum_bigint (module Circuit) x
    in
    let y =
      Foreign_field.Element.Standard.of_bignum_bigint (module Circuit) y
    in
    (x, y)

  let to_coordinates a = a

  let to_hex_as_prover (type field)
      (module Circuit : Snark_intf.Run with type field = field) a : string =
    let x, y = to_coordinates a in
    let x =
      Foreign_field.Element.Standard.to_bignum_bigint_as_prover
        (module Circuit)
        x
    in
    let y =
      Foreign_field.Element.Standard.to_bignum_bigint_as_prover
        (module Circuit)
        y
    in
    let combined = Bignum_bigint.((x * two_to_4limb) + y) in
    Common.bignum_bigint_to_hex combined

  let x a =
    let x_element, _ = to_coordinates a in
    x_element

  let y a =
    let _, y_element = to_coordinates a in
    y_element

  let equal_as_prover (type field)
      (module Circuit : Snark_intf.Run with type field = field) (left : field t)
      (right : field t) : bool =
    let left_x, left_y = to_coordinates left in
    let right_x, right_y = to_coordinates right in
    Foreign_field.Element.Standard.(
      equal_as_prover (module Circuit) left_x right_x
      && equal_as_prover (module Circuit) left_y right_y)

  let assert_equal (type field)
      (module Circuit : Snark_intf.Run with type field = field) (left : field t)
      (right : field t) : unit =
    let left_x, left_y = to_coordinates left in
    let right_x, right_y = to_coordinates right in
    Foreign_field.Element.Standard.(
      assert_equal (module Circuit) left_x right_x ;
      assert_equal (module Circuit) left_y right_y)

  let zero_as_prover (type field)
      (module Circuit : Snark_intf.Run with type field = field) : field t =
    of_coordinates
      Foreign_field.Element.Standard.
        ( of_bignum_bigint (module Circuit) Bignum_bigint.zero
        , of_bignum_bigint (module Circuit) Bignum_bigint.zero )
end

(* Array to tuple helper *)
let tuple9_of_array array =
  match array with
  | [| a1; a2; a3; a4; a5; a6; a7; a8; a9 |] ->
      (a1, a2, a3, a4, a5, a6, a7, a8, a9)
  | _ ->
      assert false

(* Helper to check if point is on elliptic curve curve: y^2 = x^3 + a * x + b *)
let is_on_curve (point : Bignum_bigint.t * Bignum_bigint.t)
    (a : Bignum_bigint.t) (* curve parameter a *)
    (b : Bignum_bigint.t) (* curve parameter b *)
    (foreign_field_modulus : Bignum_bigint.t) : bool =
  let x, y = point in
  Bignum_bigint.(
    pow y (of_int 2) % foreign_field_modulus
    = ( (pow x (of_int 3) % foreign_field_modulus)
      + (a * x % foreign_field_modulus)
      + b )
      % foreign_field_modulus)

let secp256k1_modulus =
  Common.bignum_bigint_of_hex
    "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"

(* Helper to check if point is on secp256k1 curve: y^2 = x^3 + 7 *)
let secp256k1_is_on_curve (point : Bignum_bigint.t * Bignum_bigint.t) : bool =
  is_on_curve point (Bignum_bigint.of_int 0) (Bignum_bigint.of_int 7)
    secp256k1_modulus

(* Gadget for (partial) elliptic curve group addition over foreign field
 *
 *   Given input points L and R, constrains that
 *     s = (Ry - Ly)/(Rx - Lx) mod f
 *     x = s^2 - Lx - Rx mod f
 *     y = s * (Rx - x) - Ry mod f
 *
 *   where f is the foreign field modulus.
 *   See p. 348 of "Introduction to Modern Cryptography" by Katz and Lindell
 *
 *   Preconditions and limitations:
 *     L != R
 *     Lx != Rx (no invertibility)
 *     L and R are not O (the point at infinity)
 *
 *   Supported group axioms:
 *     Closure
 *     Associativity
 *
 *   Note: We elide the Identity property because it is costly in circuit
 *         and we don't need it for our application.  By doing this we also
 *         lose Invertibility, which we also don't need for our goals.
 *)
let group_add (type f) (module Circuit : Snark_intf.Run with type field = f)
    (external_checks : f Foreign_field.External_checks.t)
    (left_input : f Affine.t) (right_input : f Affine.t)
    (foreign_field_modulus : f Foreign_field.standard_limbs) : f Affine.t =
  let open Circuit in
  (* TODO: Remove sanity checks if this API is not public facing *)
  as_prover (fun () ->
      (* Sanity check that two points are not equal *)
      assert (
        not (Affine.equal_as_prover (module Circuit) left_input right_input) ) ;
      (* Sanity check that both points are not infinity *)
      assert (
        not
          (Affine.equal_as_prover
             (module Circuit)
             left_input
             (Affine.zero_as_prover (module Circuit)) ) ) ;
      assert (
        not
          (Affine.equal_as_prover
             (module Circuit)
             right_input
             (Affine.zero_as_prover (module Circuit)) ) ) ) ;

  (* Unpack coordinates *)
  let left_x, left_y = Affine.to_coordinates left_input in
  let right_x, right_y = Affine.to_coordinates right_input in

  (* TODO: Remove sanity checks if this API is not public facing *)
  (* Sanity check that x-coordinates are not equal (i.e. we don't support Invertibility) *)
  as_prover (fun () ->
      assert (
        not
          (Foreign_field.Element.Standard.equal_as_prover
             (module Circuit)
             left_x right_x ) ) ) ;

  (* Compute witness values *)
  let ( slope0
      , slope1
      , slope2
      , result_x0
      , result_x1
      , result_x2
      , result_y0
      , result_y1
      , result_y2 ) =
    exists (Typ.array ~length:9 Field.typ) ~compute:(fun () ->
        let left_x =
          Foreign_field.Element.Standard.to_bignum_bigint_as_prover
            (module Circuit)
            left_x
        in
        let left_y =
          Foreign_field.Element.Standard.to_bignum_bigint_as_prover
            (module Circuit)
            left_y
        in
        let right_x =
          Foreign_field.Element.Standard.to_bignum_bigint_as_prover
            (module Circuit)
            right_x
        in
        let right_y =
          Foreign_field.Element.Standard.to_bignum_bigint_as_prover
            (module Circuit)
            right_y
        in
        let foreign_field_modulus =
          Foreign_field.field_standard_limbs_to_bignum_bigint
            (module Circuit)
            foreign_field_modulus
        in

        (* Compute slope and slope squared *)
        let slope =
          Bignum_bigint.(
            (* Computes s = (Ry - Ly)/(Rx - Lx) *)
            let delta_y = (right_y - left_y) % foreign_field_modulus in
            let delta_x = (right_x - left_x) % foreign_field_modulus in

            (* Compute delta_x inverse *)
            let delta_x_inv =
              Common.bignum_bigint_inverse delta_x foreign_field_modulus
            in

            delta_y * delta_x_inv % foreign_field_modulus)
        in

        let slope_squared =
          Bignum_bigint.((pow slope @@ of_int 2) % foreign_field_modulus)
        in

        (* Compute result's x-coodinate: x = s^2 - Lx - Rx *)
        let result_x =
          Bignum_bigint.(
            let slope_squared_x =
              (slope_squared - left_x) % foreign_field_modulus
            in
            (slope_squared_x - right_x) % foreign_field_modulus)
        in

        (* Compute result's y-coodinate: y = s * (Rx - x) - Ry *)
        let result_y =
          Bignum_bigint.(
            let x_diff = (right_x - result_x) % foreign_field_modulus in
            let x_diff_s = slope * x_diff % foreign_field_modulus in
            (x_diff_s - right_y) % foreign_field_modulus)
        in

        (* Convert from Bignums to field elements *)
        let slope0, slope1, slope2 =
          Foreign_field.bignum_bigint_to_field_standard_limbs
            (module Circuit)
            slope
        in
        let result_x0, result_x1, result_x2 =
          Foreign_field.bignum_bigint_to_field_standard_limbs
            (module Circuit)
            result_x
        in
        let result_y0, result_y1, result_y2 =
          Foreign_field.bignum_bigint_to_field_standard_limbs
            (module Circuit)
            result_y
        in

        (* Return and convert back to Cvars *)
        [| slope0
         ; slope1
         ; slope2
         ; result_x0
         ; result_x1
         ; result_x2
         ; result_y0
         ; result_y1
         ; result_y2
        |] )
    |> tuple9_of_array
  in

  (* Convert slope and result into foreign field elements *)
  let slope =
    Foreign_field.Element.Standard.of_limbs (slope0, slope1, slope2)
  in
  let result_x =
    Foreign_field.Element.Standard.of_limbs (result_x0, result_x1, result_x2)
  in
  let result_y =
    Foreign_field.Element.Standard.of_limbs (result_y0, result_y1, result_y2)
  in

  (* C1: Constrain computation of slope squared *)
  let slope_squared =
    (* s * s = s^2 *)
    Foreign_field.mul
      (module Circuit)
      external_checks slope slope foreign_field_modulus
  in
  (* Bounds 1: Multiplication left input (slope) and right input (slope)
   *           bound checks with single bound check.
   *           Result bound check already tracked by external_checks.
   *)
  Foreign_field.External_checks.append_bound_check external_checks
    (slope0, slope1, slope2) ;

  (* C2: Constrain result x-coordinate computation: x = s^2 - Lx - Rx with length 2 chain
   *     with s^2 - x - Lx = Rx
   *)
  let slope_squared_minus_x =
    (* s^2 - x = sΔx *)
    Foreign_field.sub
      (module Circuit)
      ~full:false slope_squared result_x foreign_field_modulus
  in
  (* Bounds 2: Left input bound check covered by (Bounds 1).
   *           Right input bound check value is gadget output so checked externally.
   *           Result chained, so no bound check required.
   *)
  let expected_right_x =
    (* sΔx - Lx = Rx *)
    Foreign_field.sub
      (module Circuit)
      ~full:false slope_squared_minus_x left_x foreign_field_modulus
  in
  (* Bounds 3: Left input bound check is chained.
   *           Right input bound check value is gadget input so checked externally.
   *)
  (* Copy expected_right_x to right_x *)
  Foreign_field.Element.Standard.assert_equal
    (module Circuit)
    expected_right_x right_x ;
  (* C3: Continue the chain to length 4 by computing (Rx - x) * s (used later) *)
  let right_delta =
    (* Rx - x = RxΔ *)
    Foreign_field.sub
      (module Circuit)
      ~full:false expected_right_x result_x foreign_field_modulus
  in
  (* Bounds 4: Addition chain result (right_delta) bound check added below.
   *           Left input bound check is chained.
   *           Right input bound check value is gadget output so checked externally.
   *)
  Foreign_field.External_checks.append_bound_check external_checks
  @@ Foreign_field.Element.Standard.to_limbs right_delta ;
  let right_delta_s =
    (* RxΔ * s = RxΔs *)
    Foreign_field.mul
      (module Circuit)
      external_checks right_delta slope foreign_field_modulus
  in

  (* Bounds 5: Multiplication result bound checks for left input (right_delta)
   *           and right input (slope) already covered by (Bounds 4) and (Bounds 1).
   *           Result bound check already tracked by external_checks.
   *)

  (* C4: Constrain slope computation: s = (Ry - Ly)/(Rx - Lx) over two length 2 chains
   *     with (Rx - Lx) * s + Ly = Ry
   *)
  let delta_x =
    (* Rx - Lx = Δx *)
    Foreign_field.sub
      (module Circuit)
      ~full:false right_x left_x foreign_field_modulus
  in
  (* Bounds 6: Addition chain result (delta_x) bound check below.
   *           Addition inputs are gadget inputs and tracked externally.
   *)
  Foreign_field.External_checks.append_bound_check external_checks
  @@ Foreign_field.Element.Standard.to_limbs delta_x ;
  let delta_x_s =
    (* Δx * s = Δxs *)
    Foreign_field.mul
      (module Circuit)
      external_checks delta_x slope foreign_field_modulus
  in
  (* Bounds 7: Multiplication bound checks for left input (delta_x) and
   *           right input (slope) are already covered by (Bounds 6) and (Bounds 1).
   *           Result bound check tracked by external_checks.
   *)
  (* Finish constraining slope in new chain (above mul ended chain) *)
  let expected_right_y =
    (* Δxs + Ly = Ry *)
    Foreign_field.add
      (module Circuit)
      ~full:false delta_x_s left_y foreign_field_modulus
  in
  (* Bounds 8: Left input bound check is tracked by (Bounds 7).
   *           Right input bound check value is gadget input so checked externally.
   *)
  (* Copy expected_right_y to right_y *)
  Foreign_field.Element.Standard.assert_equal
    (module Circuit)
    expected_right_y right_y ;
  (* C5: Constrain result y-coordinate computation: y = (Rx - x) * s - Ry
   *     with Ry + y = (Rx - x) * s
   *)
  let expected_right_delta_s =
    (* Ry + y = RxΔs *)
    Foreign_field.add ~full:false
      (module Circuit)
      expected_right_y result_y foreign_field_modulus
  in
  (* Bounds 9: Addition chain result (expected_right_delta_s) bound check already
   *           covered by (Bounds 5).
   *           Left input bound check is chained.
   *           Right input bound check value is gadget output so checked externally.
   *)
  let expected_right_delta_s0, expected_right_delta_s1, expected_right_delta_s2
      =
    Foreign_field.Element.Standard.to_limbs expected_right_delta_s
  in

  (* Final Zero gate with result *)
  with_label "group_add_final_zero_gate" (fun () ->
      assert_
        { annotation = Some __LOC__
        ; basic =
            Kimchi_backend_common.Plonk_constraint_system.Plonk_constraint.T
              (Raw
                 { kind = Zero
                 ; values =
                     [| expected_right_delta_s0
                      ; expected_right_delta_s1
                      ; expected_right_delta_s2
                     |]
                 ; coeffs = [||]
                 } )
        } ) ;
  (* Copy expected_right_delta_s to right_delta_s *)
  Foreign_field.Element.Standard.assert_equal
    (module Circuit)
    expected_right_delta_s right_delta_s ;

  (* Return result point *)
  Affine.of_coordinates (result_x, result_y)

(* Gadget for (partial) elliptic curve group doubling over foreign field
 *
 *   Given input point P, constrains that
 *     s' = 3 * Px^2 / (2 * Py) mod f
 *     x = s'^2 - 2 * Px mod f
 *     y = s' * (Px - x) - Py mod f
 *
 *   where f is the foreign field modulus.
 *   See p. 348 of "Introduction to Modern Cryptography" by Katz and Lindell
 *
 *   Preconditions and limitations:
 *      Px is not O (the point at infinity)
 *
 *   Note: See group addition notes (above) about group properties supported by this implementation
 *)
let group_double (type f) (module Circuit : Snark_intf.Run with type field = f)
    (external_checks : f Foreign_field.External_checks.t) (point : f Affine.t)
    ?(a = Circuit.Field.Constant.zero)
    (foreign_field_modulus : f Foreign_field.standard_limbs) : f Affine.t =
  let open Circuit in
  (* TODO: Remove sanity checks if this API is not public facing *)
  as_prover (fun () ->
      (* Sanity check that point is not infinity *)
      assert (
        not
          (Affine.equal_as_prover
             (module Circuit)
             point
             (Affine.zero_as_prover (module Circuit)) ) ) ) ;

  (* Unpack coordinates *)
  let point_x, point_y = Affine.to_coordinates point in

  (* Compute witness values *)
  let ( slope0
      , slope1
      , slope2
      , result_x0
      , result_x1
      , result_x2
      , result_y0
      , result_y1
      , result_y2 ) =
    exists (Typ.array ~length:9 Field.typ) ~compute:(fun () ->
        let point_x =
          Foreign_field.Element.Standard.to_bignum_bigint_as_prover
            (module Circuit)
            point_x
        in
        let point_y =
          Foreign_field.Element.Standard.to_bignum_bigint_as_prover
            (module Circuit)
            point_y
        in
        let a = Common.field_to_bignum_bigint (module Circuit) a in
        let foreign_field_modulus =
          Foreign_field.field_standard_limbs_to_bignum_bigint
            (module Circuit)
            foreign_field_modulus
        in

        (* Compute slope using 1st derivative of sqrt(x^3 + a * x + b)
         * Note that when a = 0 (e.g. as in the case of secp256k1) we have
         * one fewer constraint (below).
         *)
        let slope =
          Bignum_bigint.(
            (* Computes s' = (3 * Px^2  + a )/ 2 * Py *)
            let numerator =
              let point_x_squared =
                pow point_x (of_int 2) % foreign_field_modulus
              in
              let point_x3_squared =
                of_int 3 * point_x_squared % foreign_field_modulus
              in

              (point_x3_squared + a) % foreign_field_modulus
            in
            let denominator = of_int 2 * point_y % foreign_field_modulus in

            (* Compute inverse of denominator *)
            let denominator_inv =
              Common.bignum_bigint_inverse denominator foreign_field_modulus
            in
            numerator * denominator_inv % foreign_field_modulus)
        in

        let slope_squared =
          Bignum_bigint.((pow slope @@ of_int 2) % foreign_field_modulus)
        in

        (* Compute result's x-coodinate: x = s^2 - 2 * Px *)
        let result_x =
          Bignum_bigint.(
            let point_x2 = of_int 2 * point_x % foreign_field_modulus in
            (slope_squared - point_x2) % foreign_field_modulus)
        in

        (* Compute result's y-coodinate: y = s * (Px - x) - Py *)
        let result_y =
          Bignum_bigint.(
            let x_diff = (point_x - result_x) % foreign_field_modulus in
            let x_diff_s = slope * x_diff % foreign_field_modulus in
            (x_diff_s - point_y) % foreign_field_modulus)
        in

        (* Convert from Bignums to field elements *)
        let slope0, slope1, slope2 =
          Foreign_field.bignum_bigint_to_field_standard_limbs
            (module Circuit)
            slope
        in
        let result_x0, result_x1, result_x2 =
          Foreign_field.bignum_bigint_to_field_standard_limbs
            (module Circuit)
            result_x
        in
        let result_y0, result_y1, result_y2 =
          Foreign_field.bignum_bigint_to_field_standard_limbs
            (module Circuit)
            result_y
        in

        (* Return and convert back to Cvars *)
        [| slope0
         ; slope1
         ; slope2
         ; result_x0
         ; result_x1
         ; result_x2
         ; result_y0
         ; result_y1
         ; result_y2
        |] )
    |> tuple9_of_array
  in

  (* Convert slope and result into foreign field elements *)
  let slope =
    Foreign_field.Element.Standard.of_limbs (slope0, slope1, slope2)
  in
  let result_x =
    Foreign_field.Element.Standard.of_limbs (result_x0, result_x1, result_x2)
  in
  let result_y =
    Foreign_field.Element.Standard.of_limbs (result_y0, result_y1, result_y2)
  in

  (* C1: Constrain computation of slope squared *)
  let slope_squared =
    (* s * s  = s^2 *)
    Foreign_field.mul
      (module Circuit)
      external_checks slope slope foreign_field_modulus
  in
  (* Bounds 1: Multiplication left input (slope) and right input (slope)
   *           bound checks with single bound check.
   *           Result bound check already tracked by external_checks.
   *)
  Foreign_field.External_checks.append_bound_check external_checks
    (slope0, slope1, slope2) ;

  (* C2: Constrain result x-coordinate computation: x = s^2 - 2 * Px with length 2 chain
   *     with s^2 - x = 2 * Px
   *)
  let point_x2 =
    (* s^2 - x = 2Px *)
    Foreign_field.sub
      (module Circuit)
      ~full:false slope_squared result_x foreign_field_modulus
  in
  (* Bounds 2: Left input bound check covered by (Bounds 1).
   *           Right input bound check value is gadget output so checked externally.
   *           Result chained, so no bound check required.
   *)
  let expected_point_x =
    (* 2Px - Px = Px *)
    Foreign_field.sub
      (module Circuit)
      ~full:false point_x2 point_x foreign_field_modulus
  in
  (* Bounds 3: Left input bound check is chained.
   *           Right input bound check value is gadget input so checked externally.
   *           Result chained, so no bound check required.
   *)
  (* Copy expected_point_x to point_x *)
  Foreign_field.Element.Standard.assert_equal
    (module Circuit)
    expected_point_x point_x ;
  (* C3: Continue the chain to length 4 by computing (Px - x) * s (used later) *)
  let delta_x =
    (* Px - x = Δx *)
    Foreign_field.sub
      (module Circuit)
      ~full:false expected_point_x result_x foreign_field_modulus
  in
  (* Bounds 4: Left input bound check is chained.
   *           Right input bound check value is gadget output so checked externally.
   *           Addition chain result (delta_x) bound check added below.
   *)
  Foreign_field.External_checks.append_bound_check external_checks
  @@ Foreign_field.Element.Standard.to_limbs delta_x ;
  let delta_xs =
    (* Δx * s = Δxs *)
    Foreign_field.mul
      (module Circuit)
      external_checks delta_x slope foreign_field_modulus
  in

  (* Bounds 5: Multiplication result bound checks for left input (delta_x)
   *           and right input (slope) already covered by (Bounds 4) and (Bounds 1).
   *           Result bound check already tracked by external_checks.
   *)

  (* C4: Constrain rest of y = s' * (Px - x) - Py and part of slope computation
   *     s = (3 * Px^2 + a)/(2 * Py) in length 3 chain
   *)
  let expected_point_y =
    (* Δxs - y = Py *)
    Foreign_field.sub
      (module Circuit)
      ~full:false delta_xs result_y foreign_field_modulus
  in
  (* Bounds 6: Left input checked by (Bound 5).
   *           Right input is gadget output so checked externally.
   *           Addition result chained.
   *)
  (* Copy expected_point_y to point_y *)
  Foreign_field.Element.Standard.assert_equal
    (module Circuit)
    expected_point_y point_y ;
  let point_y2 =
    (* Py + Py = 2Py *)
    Foreign_field.add
      (module Circuit)
      ~full:false point_y point_y foreign_field_modulus
  in
  (* Bounds 7: Left input is gadget output so checked externally.
   *           Right input is gadget output so checked externally.
   *           Addition result chained.
   *)
  let point_y2s =
    (* 2Py * s = 2Pys *)
    Foreign_field.mul
      (module Circuit)
      external_checks point_y2 slope foreign_field_modulus
  in
  (* Bounds 8: Left input (point_y2) bound check added below.
   *           Right input (slope) already checked by (Bound 1).
   *           Result bound check already tracked by external_checks.
   *)
  Foreign_field.External_checks.append_bound_check external_checks
  @@ Foreign_field.Element.Standard.to_limbs point_y2 ;

  (* C5: Constrain rest slope computation s = (3 * Px^2 + a)/(2 * Py) *)
  let point_x3 =
    (* 2Px + Px = 3Px *)
    Foreign_field.add
      (module Circuit)
      ~full:false point_x2 point_x foreign_field_modulus
  in
  (* Bounds 9: Left input (point_x2) bound check added below. (TODO: double check this is necessary)
   *           Right input is gadget input so checked externally.
   *           Result chained.
   *)
  Foreign_field.External_checks.append_bound_check external_checks
  @@ Foreign_field.Element.Standard.to_limbs point_x2 ;
  let point_x3_squared =
    (* 3Px * Px = 3Px^2 *)
    Foreign_field.mul
      (module Circuit)
      external_checks point_x3 point_x foreign_field_modulus
  in

  (* Bounds 10: Left input (point_x3) bound check added below.
   *            Right input is gadget input so checked externally.
   *            Result bound check already tracked by external_checks.
   *)
  Foreign_field.External_checks.append_bound_check external_checks
  @@ Foreign_field.Element.Standard.to_limbs point_x3 ;

  (* Check if the elliptic curve a parameter requires more constraints
   * to be added in order to add final a (e.g. 3Px^2 + a where a != 0).
   *)
  ( if Field.Constant.(equal a zero) then
    (* Copy point_x3_squared to point_y2s *)
    Foreign_field.Element.Standard.assert_equal
      (module Circuit)
      point_x3_squared point_y2s
  else
    (* Add curve constant a *)
    let a =
      let a0, a1, a2 =
        exists (Typ.array ~length:3 Field.typ) ~compute:(fun () ->
            let a = Common.field_to_bignum_bigint (module Circuit) a in
            let a0, a1, a2 =
              Foreign_field.bignum_bigint_to_field_standard_limbs
                (module Circuit)
                a
            in
            [| a0; a1; a2 |] )
        |> Common.tuple3_of_array
      in
      Foreign_field.Element.Standard.of_limbs (a0, a1, a2)
    in
    (* C6: Constrain rest slope computation s = (3 * Px^2 + a)/(2 * Py) *)
    let point_x3_squared_plus_a =
      (* 3Px^2 + a = 3Px^2a *)
      Foreign_field.add
        (module Circuit)
        ~full:false point_x3_squared a foreign_field_modulus
      (* Bounds 11: Left input (point_x3_squared) already tracked by (Bounds 10).
       *            Right input is public constant. (TODO: check this)
       *            Result bound check tracked below.
       *)
    in
    Foreign_field.External_checks.append_bound_check external_checks
    @@ Foreign_field.Element.Standard.to_limbs point_x3_squared_plus_a ;

    (* Final Zero gate with result *)
    let ( point_x3_squared_plus_a0
        , point_x3_squared_plus_a1
        , point_x3_squared_plus_a2 ) =
      Foreign_field.Element.Standard.to_limbs point_x3_squared_plus_a
    in
    with_label "group_add_final_zero_gate" (fun () ->
        assert_
          { annotation = Some __LOC__
          ; basic =
              Kimchi_backend_common.Plonk_constraint_system.Plonk_constraint.T
                (Raw
                   { kind = Zero
                   ; values =
                       [| point_x3_squared_plus_a0
                        ; point_x3_squared_plus_a1
                        ; point_x3_squared_plus_a2
                       |]
                   ; coeffs = [||]
                   } )
          } ) ;

    (* Copy point_x3_squared_plus_a to point_y2s *)
    Foreign_field.Element.Standard.assert_equal
      (module Circuit)
      point_x3_squared_plus_a point_y2s ) ;

  (* Return result point *)
  Affine.of_coordinates (result_x, result_y)

(*********)
(* Tests *)
(*********)

let%test_unit "ecdsa affine helpers " =
  if (* tests_enabled *) false then
    let open Kimchi_gadgets_test_runner in
    (* Initialize the SRS cache. *)
    let () =
      try Kimchi_pasta.Vesta_based_plonk.Keypair.set_urs_info [] with _ -> ()
    in
    (* Check Affine of_hex, to_hex_as_prover and equal_as_prover *)
    let _cs, _proof_keypair, _proof =
      Runner.generate_and_verify_proof (fun () ->
          let open Runner.Impl in
          let x =
            Foreign_field.Element.Standard.of_bignum_bigint (module Runner.Impl)
            @@ Common.bignum_bigint_of_hex
                 "5945fa400436f458cb9e994dcd315ded43e9b60eb68e2ae7b5cf1d07b48ca1c"
          in
          let y =
            Foreign_field.Element.Standard.of_bignum_bigint (module Runner.Impl)
            @@ Common.bignum_bigint_of_hex
                 "69cc93598e05239aa77b85d172a9785f6f0405af91d91094f693305da68bf15"
          in
          let affine_expected = Affine.of_coordinates (x, y) in
          as_prover (fun () ->
              let affine_hex =
                Affine.to_hex_as_prover (module Runner.Impl) affine_expected
              in
              (* 5945fa400436f458cb9e994dcd315ded43e9b60eb68e2ae7b5cf1d07b48ca1c000000000000000000000000069cc93598e05239aa77b85d172a9785f6f0405af91d91094f693305da68bf15 *)
              let affine = Affine.of_hex (module Runner.Impl) affine_hex in
              assert (
                Affine.equal_as_prover
                  (module Runner.Impl)
                  affine_expected affine ) ) ;

          (* Pad with a "dummy" constraint b/c Kimchi requires at least 2 *)
          let fake =
            exists Field.typ ~compute:(fun () -> Field.Constant.zero)
          in
          Boolean.Assert.is_true (Field.equal fake Field.zero) ;
          () )
    in
    ()

let%test_unit "group_add" =
  if (* tests_enabled *) false then (
    let open Kimchi_gadgets_test_runner in
    (* Initialize the SRS cache. *)
    let () =
      try Kimchi_pasta.Vesta_based_plonk.Keypair.set_urs_info [] with _ -> ()
    in

    (* Test group add *)
    let test_group_add ?cs (left_input : Bignum_bigint.t * Bignum_bigint.t)
        (right_input : Bignum_bigint.t * Bignum_bigint.t)
        (expected_result : Bignum_bigint.t * Bignum_bigint.t)
        (foreign_field_modulus : Bignum_bigint.t) =
      (* Generate and verify proof *)
      let cs, _proof_keypair, _proof =
        Runner.generate_and_verify_proof ?cs (fun () ->
            let open Runner.Impl in
            (* Prepare test inputs *)
            let foreign_field_modulus =
              Foreign_field.bignum_bigint_to_field_standard_limbs
                (module Runner.Impl)
                foreign_field_modulus
            in
            let left_input =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                left_input
            in
            let right_input =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                right_input
            in
            let expected_result =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                expected_result
            in

            (* Create external checks context for tracking extra constraints
               that are required for soundness (unused in this simple test) *)
            let unused_external_checks =
              Foreign_field.External_checks.create (module Runner.Impl)
            in

            (* L + R = S *)
            let result =
              group_add
                (module Runner.Impl)
                unused_external_checks left_input right_input
                foreign_field_modulus
            in

            (* Check for expected quantity of external checks *)
            assert (
              Mina_stdlib.List.Length.equal unused_external_checks.bounds 6 ) ;
            assert (
              Mina_stdlib.List.Length.equal unused_external_checks.multi_ranges
                3 ) ;
            assert (
              Mina_stdlib.List.Length.equal
                unused_external_checks.compact_multi_ranges 3 ) ;

            (* Check output matches expected result *)
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    result expected_result ) ) ;
            () )
      in

      cs
    in

    (* Tests for random points *)
    let _cs =
      test_group_add
        (Bignum_bigint.of_int 4, Bignum_bigint.one) (* left_input *)
        (Bignum_bigint.of_int 0, Bignum_bigint.of_int 3) (* right_input *)
        (Bignum_bigint.of_int 0, Bignum_bigint.of_int 2) (* expected result *)
        (Bignum_bigint.of_int 5)
    in
    let _cs =
      test_group_add
        (Bignum_bigint.of_int 2, Bignum_bigint.of_int 3) (* left_input *)
        (Bignum_bigint.of_int 1, Bignum_bigint.of_int 0) (* right_input *)
        (Bignum_bigint.of_int 1, Bignum_bigint.of_int 0) (* expected result *)
        (Bignum_bigint.of_int 5)
    in

    (* Constraint system reuse tests *)
    let cs =
      test_group_add
        (Bignum_bigint.of_int 3, Bignum_bigint.of_int 8) (* left_input *)
        (Bignum_bigint.of_int 5, Bignum_bigint.of_int 11) (* right_input *)
        (Bignum_bigint.of_int 4, Bignum_bigint.of_int 10) (* expected result *)
        (Bignum_bigint.of_int 13)
    in
    let _cs =
      test_group_add ~cs
        (Bignum_bigint.of_int 10, Bignum_bigint.of_int 4) (* left_input *)
        (Bignum_bigint.of_int 12, Bignum_bigint.of_int 7) (* right_input *)
        (Bignum_bigint.of_int 3, Bignum_bigint.of_int 0) (* expected result *)
        (Bignum_bigint.of_int 13)
    in
    let _cs =
      test_group_add ~cs
        (Bignum_bigint.of_int 8, Bignum_bigint.of_int 6) (* left_input *)
        (Bignum_bigint.of_int 2, Bignum_bigint.of_int 1) (* right_input *)
        (Bignum_bigint.of_int 12, Bignum_bigint.of_int 8) (* expected result *)
        (Bignum_bigint.of_int 13)
    in

    (* Negative tests *)
    assert (
      Common.is_error (fun () ->
          (* Wrong constraint system (changed modulus) *)
          test_group_add ~cs
            (Bignum_bigint.of_int 8, Bignum_bigint.of_int 6) (* left_input *)
            (Bignum_bigint.of_int 2, Bignum_bigint.of_int 1) (* right_input *)
            (Bignum_bigint.of_int 12, Bignum_bigint.of_int 8)
            (* expected result *)
            (Bignum_bigint.of_int 9) ) ) ;
    assert (
      Common.is_error (fun () ->
          (* Wrong answer (right modulus) *)
          test_group_add ~cs
            (Bignum_bigint.of_int 8, Bignum_bigint.of_int 6) (* left_input *)
            (Bignum_bigint.of_int 2, Bignum_bigint.of_int 1) (* right_input *)
            (Bignum_bigint.of_int 12, Bignum_bigint.of_int 9)
            (* expected result *)
            (Bignum_bigint.of_int 13) ) ) ;

    (* Tests with secp256k1 curve points *)
    let secp256k1_generator =
      ( Bignum_bigint.of_string
          "55066263022277343669578718895168534326250603453777594175500187360389116729240"
      , Bignum_bigint.of_string
          "32670510020758816978083085130507043184471273380659243275938904335757337482424"
      )
    in

    let random_point1 =
      ( Bignum_bigint.of_string
          "11498799051185379176527662983290644419148625795866197242742376646044820710107"
      , Bignum_bigint.of_string
          "87365548140897354715632623292744880448736648603030553868546115582681395400362"
      )
    in
    let expected_result1 =
      ( Bignum_bigint.of_string
          "29271032301589161601163082898984274448470999636237808164579416118817375265766"
      , Bignum_bigint.of_string
          "70576057075545750224511488165986665682391544714639291167940534165970533739040"
      )
    in

    assert (secp256k1_is_on_curve secp256k1_generator) ;
    assert (secp256k1_is_on_curve random_point1) ;
    assert (secp256k1_is_on_curve expected_result1) ;

    let _cs =
      test_group_add random_point1 (* left_input *)
        secp256k1_generator (* right_input *)
        expected_result1 (* expected result *)
        secp256k1_modulus
    in

    let random_point2 =
      ( Bignum_bigint.of_string
          "112776793647017636286801498409683698782792816810143189200772003475655331235512"
      , Bignum_bigint.of_string
          "37154006933110560524528936279434506593302537023736551486562363002969014272200"
      )
    in
    let expected_result2 =
      ( Bignum_bigint.of_string
          "80919512080552099332189419005806362073658070117780992417768444957631350640350"
      , Bignum_bigint.of_string
          "4839884697531819803579082430572588557482298603278351225895977263486959680227"
      )
    in

    assert (secp256k1_is_on_curve random_point2) ;
    assert (secp256k1_is_on_curve expected_result2) ;

    let _cs =
      test_group_add expected_result1 (* left_input *)
        random_point2 (* right_input *)
        expected_result2 (* expected result *)
        secp256k1_modulus
    in

    let random_point3 =
      ( Bignum_bigint.of_string
          "36425953153418322223243576029807183106978427220826420108023201968296177476778"
      , Bignum_bigint.of_string
          "24007339127999344540320969916238304309192480878642453507169699691156248304362"
      )
    in
    let random_point4 =
      ( Bignum_bigint.of_string
          "21639969699195480792170626687481368104641445608975892798617312168630290254356"
      , Bignum_bigint.of_string
          "30444719434143548339668041811488444063562085329168372025420048436035175999301"
      )
    in
    let expected_result3 =
      ( Bignum_bigint.of_string
          "113188224115387667795245114738521133409188389625511152470086031332181459812059"
      , Bignum_bigint.of_string
          "82989616646064102138003387261138741187755389122561858439662322580504431694519"
      )
    in

    assert (secp256k1_is_on_curve random_point3) ;
    assert (secp256k1_is_on_curve random_point4) ;
    assert (secp256k1_is_on_curve expected_result3) ;

    let _cs =
      test_group_add random_point3 (* left_input *)
        random_point4 (* right_input *)
        expected_result3 (* expected result *)
        secp256k1_modulus
    in

    (* Constraint system reuse tests *)
    let pt1 =
      ( Bignum_bigint.of_string
          "75669526378790147634671888414445173066514756807031971924620136884638031442759"
      , Bignum_bigint.of_string
          "21417425897684876536576718477824646351185804513111016365368704154638046645765"
      )
    in
    let pt2 =
      ( Bignum_bigint.of_string
          "14155322613096941824503892607495280579903778637099750589312382650686697414735"
      , Bignum_bigint.of_string
          "6513771125762614571725090849784101711151222857564970563886992272283710338112"
      )
    in
    let expected_pt =
      ( Bignum_bigint.of_string
          "11234404138675683238798732023399338183955476104311735089175934636931978267582"
      , Bignum_bigint.of_string
          "2483077095355421104741807026372550508534866555013063406887316930008225336894"
      )
    in

    assert (secp256k1_is_on_curve pt1) ;
    assert (secp256k1_is_on_curve pt2) ;
    assert (secp256k1_is_on_curve expected_pt) ;

    let cs =
      test_group_add pt1 (* left_input *)
        pt2 (* right_input *)
        expected_pt (* expected result *)
        secp256k1_modulus
    in

    let pt1 =
      ( Bignum_bigint.of_string
          "97313026812541560473771297589757921196424145769025529099070592800256734650744"
      , Bignum_bigint.of_string
          "38700860102018844310665941222140210385381782344695476706452234109902874948789"
      )
    in
    let pt2 =
      ( Bignum_bigint.of_string
          "82416105962835331584090450180444085592428397648594295814088133554696721893017"
      , Bignum_bigint.of_string
          "72361514636959418409520767179749571220723219394228755075988292395103362307597"
      )
    in
    let expected_pt =
      ( Bignum_bigint.of_string
          "63066162743654726673830060769616154872212462240062945169518526070045923596428"
      , Bignum_bigint.of_string
          "54808797958010370431464079583774910620962703868682659560981623451275441505706"
      )
    in

    assert (secp256k1_is_on_curve pt1) ;
    assert (secp256k1_is_on_curve pt2) ;
    assert (secp256k1_is_on_curve expected_pt) ;

    let _cs =
      test_group_add ~cs pt1 (* left_input *)
        pt2 (* right_input *)
        expected_pt (* expected result *)
        secp256k1_modulus
    in

    let expected2 =
      ( Bignum_bigint.of_string
          "23989387498834566531803335539224216637656125335573670100510541031866883369583"
      , Bignum_bigint.of_string
          "8780199033752628541949962988447578555155504633890539264032735153636423550500"
      )
    in

    assert (secp256k1_is_on_curve expected2) ;

    let _cs =
      test_group_add ~cs expected_pt (* left_input *)
        pt1 (* right_input *)
        expected2 (* expected result *)
        secp256k1_modulus
    in

    (* Negative tests *)
    assert (
      Common.is_error (fun () ->
          (* Wrong constraint system (changed modulus) *)
          test_group_add ~cs expected_pt (* left_input *)
            pt1 (* right_input *)
            expected2
            (* expected result *)
            (Bignum_bigint.of_int 9) ) ) ;

    assert (
      Common.is_error (fun () ->
          (* Wrong result *)
          test_group_add ~cs expected_pt (* left_input *)
            pt1 (* right_input *)
            expected_pt (* expected result *)
            secp256k1_modulus ) ) ;

    (* Test with some real Ethereum curve points *)

    (* Curve point from pubkey of sender of 1st Ethereum transcation
     * https://etherscan.io/tx/0x5c504ed432cb51138bcf09aa5e8a410dd4a1e204ef84bfed1be16dfba1b22060
     *)
    let first_eth_tx_pubkey =
      ( Bignum_bigint.of_string
          "25074680562105920500390488848505179172301959433246133200656053822731415560379"
      , Bignum_bigint.of_string
          "40207352835024964935479287038185466710938760823387493786206830664631160762596"
      )
    in
    (* Vb pubkey curve point
     * https://etherscan.io/address/0xab5801a7d398351b8be11c439e05c5b3259aec9b
     *)
    let vitalik_eth_pubkey =
      ( Bignum_bigint.of_string
          "49781623198970027997721070672560275063607048368575198229673025608762959476014"
      , Bignum_bigint.of_string
          "44999051047832679156664607491606359183507784636787036192076848057884504239143"
      )
    in
    let expected_result =
      ( Bignum_bigint.of_string
          "5673019186984644139884227978304592898127494693953507135947623290000290975721"
      , Bignum_bigint.of_string
          "63149760798259320533576297417560108418144118481056410815317549443093209180466"
      )
    in

    assert (secp256k1_is_on_curve first_eth_tx_pubkey) ;
    assert (secp256k1_is_on_curve vitalik_eth_pubkey) ;
    assert (secp256k1_is_on_curve expected_result) ;

    let _cs =
      test_group_add ~cs first_eth_tx_pubkey (* left_input *)
        vitalik_eth_pubkey (* right_input *)
        expected_result (* expected result *)
        secp256k1_modulus
    in

    () )

let%test_unit "group_add_chained" =
  if (* tests_enabled *) false then (
    let open Kimchi_gadgets_test_runner in
    (* Initialize the SRS cache. *)
    let () =
      try Kimchi_pasta.Vesta_based_plonk.Keypair.set_urs_info [] with _ -> ()
    in

    (* Test chained group add *)
    let test_group_add_chained ?cs ?(chain_left = true)
        (left_input : Bignum_bigint.t * Bignum_bigint.t)
        (right_input : Bignum_bigint.t * Bignum_bigint.t)
        (input2 : Bignum_bigint.t * Bignum_bigint.t)
        (expected_result : Bignum_bigint.t * Bignum_bigint.t)
        (foreign_field_modulus : Bignum_bigint.t) =
      (* Generate and verify proof *)
      let cs, _proof_keypair, _proof =
        Runner.generate_and_verify_proof ?cs (fun () ->
            let open Runner.Impl in
            (* Prepare test inputs *)
            let foreign_field_modulus =
              Foreign_field.bignum_bigint_to_field_standard_limbs
                (module Runner.Impl)
                foreign_field_modulus
            in
            let left_input =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                left_input
            in
            let right_input =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                right_input
            in
            let input2 =
              Affine.of_bignum_bigint_coordinates (module Runner.Impl) input2
            in
            let expected_result =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                expected_result
            in

            (* Create external checks context for tracking extra constraints
             * that are required for soundness (unused in this test) *)
            let unused_external_checks =
              Foreign_field.External_checks.create (module Runner.Impl)
            in

            (* L + R = S *)
            let result1 =
              group_add
                (module Runner.Impl)
                unused_external_checks left_input right_input
                foreign_field_modulus
            in

            let result2 =
              if chain_left then
                (* S + T = U *)
                (* Chain result to left input *)
                group_add
                  (module Runner.Impl)
                  unused_external_checks result1 input2 foreign_field_modulus
              else
                (* Chain result to right input *)
                (* T + S = U *)
                group_add
                  (module Runner.Impl)
                  unused_external_checks input2 result1 foreign_field_modulus
            in

            (* Check for expected quantity of external checks *)
            assert (
              Mina_stdlib.List.Length.equal unused_external_checks.bounds 12 ) ;
            assert (
              Mina_stdlib.List.Length.equal unused_external_checks.multi_ranges
                6 ) ;
            assert (
              Mina_stdlib.List.Length.equal
                unused_external_checks.compact_multi_ranges 6 ) ;

            (* Check output matches expected result *)
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    result2 expected_result ) ) ;
            () )
      in

      cs
    in

    (* Group add chaining test *)
    let pt1 =
      ( Bignum_bigint.of_string
          "22078445491128279362564324454450148838521766213873448035670368771866784776689"
      , Bignum_bigint.of_string
          "59164395213226911607629035235242369632135709209315776938135875644072412604417"
      )
    in
    let pt2 =
      ( Bignum_bigint.of_string
          "43363091675487122074415344565583111028231348930161176231597524718735106294021"
      , Bignum_bigint.of_string
          "111622036424234525038201689158418296167019583124308154759441266557529051647503"
      )
    in
    let pt3 =
      ( Bignum_bigint.of_string
          "27095120504150867682043281371962577090258298278269412698577541627879567814209"
      , Bignum_bigint.of_string
          "43319029043781297382854244012410471023426320563005937780035785457494374919933"
      )
    in
    let expected =
      ( Bignum_bigint.of_string
          "94445004776077869359279503733865512156009118507534561304362934747962270973982"
      , Bignum_bigint.of_string
          "5771544338553827547535594828872899427364500537732448576560233867747655654290"
      )
    in

    assert (secp256k1_is_on_curve pt1) ;
    assert (secp256k1_is_on_curve pt2) ;
    assert (secp256k1_is_on_curve pt3) ;
    assert (secp256k1_is_on_curve expected) ;

    (* Correct wiring for left chaining
     *   Result r1 = pt1 + pt2 and left operand of r2 = r1 + pt3
     *
     *     ,--------------------------------------------,
     * x0: `-> (2, 3) -> (4, 3) -> (20, 3) -> (16, 3) ->`
     *          r1x0      r1x0       Lx0        Lx0
     *
     *     ,--------------------------------------------,
     * x1: `-> (2, 4) -> (16, 4) -> (20, 4) -> (4, 4) ->`
     *          r1x1       Lx1        Lx1       r1x1
     *
     *     ,--------------------------------------------,
     * x2: `-> (2, 5) -> (20, 5) -> (4, 5) -> (16, 5) ->`
     *          r1x2       Lx2       r1x2       Lx2
     *
     *     ,------------------------,
     * y0: `-> (11, 3) -> (23, 3) ->`
     *          r1y0        Ly0
     *
     *     ,------------------------,
     * y1: `-> (11, 4) -> (23, 4) ->`
     *          r1y1        Ly1
     *
     *     ,------------------------,
     * y2: `-> (11, 5) -> (23, 5) ->`
     *          r1y2        Ly2
     *)
    let _cs =
      test_group_add_chained pt1 (* left_input *)
        pt2 (* right_input *)
        pt3 (* input2 *)
        expected (* expected result *)
        secp256k1_modulus
    in

    (* Correct wiring for right chaining
     *   Result r1 = pt1 + pt2 and right operand of r2 = pt3 + r1
     *
     *     ,-------------------------------------------,
     * x0: `-> (2, 3) -> (17, 0) -> (4, 3) -> (20, 0) /
     *          r1x0       Rx0       r1x0       Rx0
     *
     *     ,-------------------------------------------,
     * x1: `-> (2, 4) -> (17, 1) -> (20, 1) -> (4, 4) /
     *          r1x1       Rx1        Rx1       r1x1
     *
     *     ,-------------------------------------------,
     * x2: `-> (2, 5) -> (4, 5) -> (17, 2) -> (20, 2) /
     *          r1x2      r1x2       Rx2        Rx2
     *
     *     ,------------------------,
     * y0: `-> (11, 3) -> (24, 0) ->`
     *          r1y0        Ry0
     *
     *     ,------------------------,
     * y1: `-> (11, 4) -> (24, 1) ->`
     *          r1y1        Ry1
     *
     *     ,------------------------,
     * y2: `-> (11, 5) -> (24, 2) ->`
     *          r1y2        Ry2
     *)
    let _cs =
      test_group_add_chained ~chain_left:false pt1 (* left_input *)
        pt2 (* right_input *)
        pt3 (* input2 *)
        expected (* expected result *)
        secp256k1_modulus
    in
    () )

let%test_unit "group_add_full" =
  if (* tests_enabled *) false then (
    let open Kimchi_gadgets_test_runner in
    (* Initialize the SRS cache. *)
    let () =
      try Kimchi_pasta.Vesta_based_plonk.Keypair.set_urs_info [] with _ -> ()
    in

    (* Test full group add (with bounds cehcks) *)
    let test_group_add_full ?cs (left_input : Bignum_bigint.t * Bignum_bigint.t)
        (right_input : Bignum_bigint.t * Bignum_bigint.t)
        (expected_result : Bignum_bigint.t * Bignum_bigint.t)
        (foreign_field_modulus : Bignum_bigint.t) =
      (* Generate and verify proof *)
      let cs, _proof_keypair, _proof =
        Runner.generate_and_verify_proof ?cs (fun () ->
            let open Runner.Impl in
            (* Prepare test inputs *)
            let foreign_field_modulus =
              Foreign_field.bignum_bigint_to_field_standard_limbs
                (module Runner.Impl)
                foreign_field_modulus
            in
            let left_input =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                left_input
            in
            let right_input =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                right_input
            in
            let expected_result =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                expected_result
            in

            (* Create external checks context for tracking extra constraints
               that are required for soundness *)
            let external_checks =
              Foreign_field.External_checks.create (module Runner.Impl)
            in

            (* L + R = S *)
            let result =
              group_add
                (module Runner.Impl)
                external_checks left_input right_input foreign_field_modulus
            in

            (* Add left_input to external checks *)
            Foreign_field.(
              External_checks.append_bound_check external_checks
              @@ Element.Standard.to_limbs @@ Affine.x left_input) ;
            Foreign_field.(
              External_checks.append_bound_check external_checks
              @@ Element.Standard.to_limbs @@ Affine.y left_input) ;

            (* Add right_input to external checks *)
            Foreign_field.(
              External_checks.append_bound_check external_checks
              @@ Element.Standard.to_limbs @@ Affine.x right_input) ;
            Foreign_field.(
              External_checks.append_bound_check external_checks
              @@ Element.Standard.to_limbs @@ Affine.y right_input) ;

            (* Add result to external checks *)
            Foreign_field.(
              External_checks.append_bound_check external_checks
              @@ Element.Standard.to_limbs @@ Affine.x result) ;
            Foreign_field.(
              External_checks.append_bound_check external_checks
              @@ Element.Standard.to_limbs @@ Affine.y result) ;

            (* Check output matches expected result *)
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    result expected_result ) ) ;

            (* Perform external checks *)
            (* 1) Add gates for external bound additions.
             *    Note: internally this also adds multi-range-checks for the
             *    computed bound to the external_checks.multi-ranges, which
             *    are then constrainted in (2)
             *)
            assert (Mina_stdlib.List.Length.equal external_checks.bounds 12) ;
            List.iter external_checks.bounds ~f:(fun product ->
                let _remainder_bound =
                  Foreign_field.valid_element
                    (module Runner.Impl)
                    external_checks
                    (Foreign_field.Element.Standard.of_limbs product)
                    foreign_field_modulus
                in
                () ) ;

            (* 2) Add gates for external multi-range-checks *)
            assert (
              Mina_stdlib.List.Length.equal external_checks.multi_ranges 15 ) ;
            List.iter external_checks.multi_ranges ~f:(fun multi_range ->
                let v0, v1, v2 = multi_range in
                Range_check.multi (module Runner.Impl) v0 v1 v2 ;
                () ) ;

            (* 3) Add gates for external compact-multi-range-checks *)
            assert (
              Mina_stdlib.List.Length.equal external_checks.compact_multi_ranges
                3 ) ;
            List.iter external_checks.compact_multi_ranges
              ~f:(fun compact_multi_range ->
                let v01, v2 = compact_multi_range in
                Range_check.compact_multi (module Runner.Impl) v01 v2 ;
                () ) ;
            () )
      in
      cs
    in

    (* Full tests *)
    let pt1 =
      ( Bignum_bigint.of_string
          "108106717441068942935036481412556424456551432537879152449804306833272168535105"
      , Bignum_bigint.of_string
          "76460339884983741488305111710326981694475523676336423409829095132008854584808"
      )
    in
    let pt2 =
      ( Bignum_bigint.of_string
          "6918332104414828558125020939363051148342349799951368824506926403525772818971"
      , Bignum_bigint.of_string
          "112511987857588994657806651103271803396616867673371823390960630078201657435176"
      )
    in
    let expected =
      ( Bignum_bigint.of_string
          "87351883076573600335277375022118065102135008483181597654369109297980597321941"
      , Bignum_bigint.of_string
          "42323967499650833993389664859011147254281400152806022789809987122536303627261"
      )
    in

    assert (secp256k1_is_on_curve pt1) ;
    assert (secp256k1_is_on_curve pt2) ;
    assert (secp256k1_is_on_curve expected) ;

    let _cs =
      test_group_add_full pt1 (* left_input *)
        pt2 (* right_input *)
        expected (* expected result *)
        secp256k1_modulus
    in
    () )

let%test_unit "group_double" =
  if (* tests_enabled *) false then (
    let open Kimchi_gadgets_test_runner in
    (* Initialize the SRS cache. *)
    let () =
      try Kimchi_pasta.Vesta_based_plonk.Keypair.set_urs_info [] with _ -> ()
    in

    (* Test group double *)
    let test_group_double ?cs (point : Bignum_bigint.t * Bignum_bigint.t)
        (expected_result : Bignum_bigint.t * Bignum_bigint.t)
        ?(a = Bignum_bigint.zero)
        (* curve parameter a *)
          (foreign_field_modulus : Bignum_bigint.t) =
      (* Generate and verify proof *)
      let cs, _proof_keypair, _proof =
        Runner.generate_and_verify_proof ?cs (fun () ->
            let open Runner.Impl in
            let a = Common.bignum_bigint_to_field (module Runner.Impl) a in
            (* Prepare test inputs *)
            let foreign_field_modulus =
              Foreign_field.bignum_bigint_to_field_standard_limbs
                (module Runner.Impl)
                foreign_field_modulus
            in
            let point =
              Affine.of_bignum_bigint_coordinates (module Runner.Impl) point
            in
            let expected_result =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                expected_result
            in

            (* Create external checks context for tracking extra constraints
               that are required for soundness (unused in this simple test) *)
            let unused_external_checks =
              Foreign_field.External_checks.create (module Runner.Impl)
            in

            (* P + P = D *)
            let result =
              group_double
                (module Runner.Impl)
                unused_external_checks point ~a foreign_field_modulus
            in

            (* Check for expected quantity of external checks *)
            if Field.Constant.(equal a zero) then
              assert (
                Mina_stdlib.List.Length.equal unused_external_checks.bounds 9 )
            else
              assert (
                Mina_stdlib.List.Length.equal unused_external_checks.bounds 10 ) ;
            assert (
              Mina_stdlib.List.Length.equal unused_external_checks.multi_ranges
                4 ) ;
            assert (
              Mina_stdlib.List.Length.equal
                unused_external_checks.compact_multi_ranges 4 ) ;

            (* Check output matches expected result *)
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    result expected_result ) ) ;
            () )
      in

      cs
    in

    (* Test with elliptic curve y^2 = x^3 + 2 * x + 5 mod 13 *)
    let _cs =
      let a = Bignum_bigint.of_int 2 in
      let b = Bignum_bigint.of_int 5 in
      let modulus = Bignum_bigint.of_int 13 in
      let point = (Bignum_bigint.of_int 2, Bignum_bigint.of_int 2) in
      let expected_result = (Bignum_bigint.of_int 5, Bignum_bigint.of_int 7) in
      assert (is_on_curve point a b modulus) ;
      assert (is_on_curve expected_result a b modulus) ;
      test_group_double point (* point *)
        expected_result (* expected result *)
        ~a modulus
    in

    (* Test with elliptic curve y^2 = x^3 + 5 mod 13 *)
    let _cs =
      let a = Bignum_bigint.of_int 0 in
      let b = Bignum_bigint.of_int 5 in
      let modulus = Bignum_bigint.of_int 13 in
      let point = (Bignum_bigint.of_int 4, Bignum_bigint.of_int 2) in
      let expected_result = (Bignum_bigint.of_int 6, Bignum_bigint.of_int 0) in
      assert (is_on_curve point a b modulus) ;
      assert (is_on_curve expected_result a b modulus) ;
      test_group_double point (* point *)
        expected_result (* expected result *)
        modulus
    in

    (* Test with elliptic curve y^2 = x^3 + 7 mod 13 *)
    let cs0 =
      let a = Bignum_bigint.of_int 0 in
      let b = Bignum_bigint.of_int 7 in
      let modulus = Bignum_bigint.of_int 13 in
      let point = (Bignum_bigint.of_int 7, Bignum_bigint.of_int 8) in
      let expected_result = (Bignum_bigint.of_int 8, Bignum_bigint.of_int 8) in
      assert (is_on_curve point a b modulus) ;
      assert (is_on_curve expected_result a b modulus) ;
      let cs =
        test_group_double point (* point *)
          expected_result (* expected result *)
          modulus
      in
      let _cs =
        test_group_double point (* point *)
          expected_result (* expected result *)
          ~a modulus
      in
      cs
    in

    (* Test with elliptic curve y^2 = x^3 + 17 * x mod 7879 *)
    let cs17 =
      let a = Bignum_bigint.of_int 17 in
      let b = Bignum_bigint.of_int 0 in
      let modulus = Bignum_bigint.of_int 7879 in
      let point = (Bignum_bigint.of_int 7331, Bignum_bigint.of_int 888) in
      let expected_result =
        (Bignum_bigint.of_int 2754, Bignum_bigint.of_int 3623)
      in
      assert (is_on_curve point a b modulus) ;
      assert (is_on_curve expected_result a b modulus) ;
      test_group_double point (* point *)
        expected_result (* expected result *)
        ~a modulus
    in

    (* Constraint system reuse tests *)
    let _cs =
      let a = Bignum_bigint.of_int 0 in
      let b = Bignum_bigint.of_int 7 in
      let modulus = Bignum_bigint.of_int 13 in
      let point = (Bignum_bigint.of_int 8, Bignum_bigint.of_int 8) in
      let expected_result = (Bignum_bigint.of_int 11, Bignum_bigint.of_int 8) in
      assert (is_on_curve point a b modulus) ;
      assert (is_on_curve expected_result a b modulus) ;
      test_group_double ~cs:cs0 point (* point *)
        expected_result (* expected result *)
        ~a modulus
    in

    let _cs =
      let a = Bignum_bigint.of_int 17 in
      let b = Bignum_bigint.of_int 0 in
      let modulus = Bignum_bigint.of_int 7879 in
      let point = (Bignum_bigint.of_int 1729, Bignum_bigint.of_int 4830) in
      let expected_result =
        (Bignum_bigint.of_int 6020, Bignum_bigint.of_int 5832)
      in
      assert (is_on_curve point a b modulus) ;
      assert (is_on_curve expected_result a b modulus) ;
      let _cs =
        test_group_double ~cs:cs17 point (* point *)
          expected_result (* expected result *)
          ~a modulus
      in

      (* Negative test *)
      assert (
        Common.is_error (fun () ->
            (* Wrong constraint system *)
            test_group_double ~cs:cs0 point (* point *)
              expected_result (* expected result *)
              ~a modulus ) ) ;
      _cs
    in

    (* Tests with secp256k1 curve points *)
    let point =
      ( Bignum_bigint.of_string
          "107002484780363838095534061209472738804517997328105554367794569298664989358181"
      , Bignum_bigint.of_string
          "92879551684948148252506282887871578114014191438980334462241462418477012406178"
      )
    in
    let expected_result =
      ( Bignum_bigint.of_string
          "74712964529040634650603708923084871318006229334056222485473734005356559517441"
      , Bignum_bigint.of_string
          "115267803285637743262834568062293432343366237647730050692079006689357117890542"
      )
    in

    assert (secp256k1_is_on_curve point) ;
    assert (secp256k1_is_on_curve expected_result) ;

    let _cs = test_group_double point expected_result secp256k1_modulus in

    let secp256k1_generator =
      ( Bignum_bigint.of_string
          "55066263022277343669578718895168534326250603453777594175500187360389116729240"
      , Bignum_bigint.of_string
          "32670510020758816978083085130507043184471273380659243275938904335757337482424"
      )
    in
    let expected_result =
      ( Bignum_bigint.of_string
          "89565891926547004231252920425935692360644145829622209833684329913297188986597"
      , Bignum_bigint.of_string
          "12158399299693830322967808612713398636155367887041628176798871954788371653930"
      )
    in

    assert (secp256k1_is_on_curve secp256k1_generator) ;
    assert (secp256k1_is_on_curve expected_result) ;

    let _cs =
      test_group_double secp256k1_generator expected_result secp256k1_modulus
    in

    let point =
      ( Bignum_bigint.of_string
          "72340565915695963948758748585975158634181237057659908187426872555266933736285"
      , Bignum_bigint.of_string
          "26612022505003328753510360357395054342310218908477055087761596777225815854353"
      )
    in
    let expected_result =
      ( Bignum_bigint.of_string
          "108904232316543774780790055701972437888102004393747607639914151522482739421637"
      , Bignum_bigint.of_string
          "12361022197403188621809379658301822420116828257004558379520642349031207949605"
      )
    in

    assert (secp256k1_is_on_curve point) ;
    assert (secp256k1_is_on_curve expected_result) ;

    let _cs = test_group_double point expected_result secp256k1_modulus in

    let point =
      ( Bignum_bigint.of_string
          "108904232316543774780790055701972437888102004393747607639914151522482739421637"
      , Bignum_bigint.of_string
          "12361022197403188621809379658301822420116828257004558379520642349031207949605"
      )
    in
    let expected_result =
      ( Bignum_bigint.of_string
          "6412514063090203022225668498768852033918664033020116827066881895897922497918"
      , Bignum_bigint.of_string
          "46730676600197705465960490527225757352559615957463874893868944815778370642915"
      )
    in
    assert (secp256k1_is_on_curve point) ;
    assert (secp256k1_is_on_curve expected_result) ;

    let cs = test_group_double point expected_result secp256k1_modulus in

    (* CS reuse again*)
    let point =
      ( Bignum_bigint.of_string
          "3994127195658013268703905225007935609302368792888634855477505418126918261961"
      , Bignum_bigint.of_string
          "25535899907968670181603106060653290873698485840006655398881908734054954693109"
      )
    in
    let expected_result =
      ( Bignum_bigint.of_string
          "85505889528097925687832670439248941652336655858213625210338216314923495678594"
      , Bignum_bigint.of_string
          "49191910521103183437466384378802260055879125327516949990516385020354020159575"
      )
    in
    assert (secp256k1_is_on_curve point) ;
    assert (secp256k1_is_on_curve expected_result) ;

    let _cs = test_group_double ~cs point expected_result secp256k1_modulus in

    (* Negative tests *)
    assert (
      Common.is_error (fun () ->
          (* Wrong constraint system *)
          test_group_double ~cs:cs0 point (* point *)
            expected_result (* expected result *)
            secp256k1_modulus ) ) ;

    assert (
      Common.is_error (fun () ->
          (* Wrong answer *)
          let wrong_result =
            ( Bignum_bigint.of_string
                "6412514063090203022225668498768852033918664033020116827066881895897922497918"
            , Bignum_bigint.of_string
                "46730676600197705465960490527225757352559615957463874893868944815778370642914"
            )
          in
          test_group_double point (* point *)
            wrong_result (* expected result *)
            secp256k1_modulus ) ) ;

    () )

let%test_unit "group_double_chained" =
  if (* tests_enabled *) false then (
    let open Kimchi_gadgets_test_runner in
    (* Initialize the SRS cache. *)
    let () =
      try Kimchi_pasta.Vesta_based_plonk.Keypair.set_urs_info [] with _ -> ()
    in

    (* Test group double chaining *)
    let test_group_double_chained ?cs
        (point : Bignum_bigint.t * Bignum_bigint.t)
        (expected_result : Bignum_bigint.t * Bignum_bigint.t)
        ?(a = Bignum_bigint.zero)
        (* curve parameter a *)
          (foreign_field_modulus : Bignum_bigint.t) =
      (* Generate and verify proof *)
      let cs, _proof_keypair, _proof =
        Runner.generate_and_verify_proof ?cs (fun () ->
            let open Runner.Impl in
            let a = Common.bignum_bigint_to_field (module Runner.Impl) a in
            (* Prepare test inputs *)
            let foreign_field_modulus =
              Foreign_field.bignum_bigint_to_field_standard_limbs
                (module Runner.Impl)
                foreign_field_modulus
            in
            let point =
              Affine.of_bignum_bigint_coordinates (module Runner.Impl) point
            in
            let expected_result =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                expected_result
            in

            (* Create external checks context for tracking extra constraints
               that are required for soundness (unused in this simple test) *)
            let unused_external_checks =
              Foreign_field.External_checks.create (module Runner.Impl)
            in

            let result =
              group_double
                (module Runner.Impl)
                unused_external_checks point ~a foreign_field_modulus
            in
            let result =
              group_double
                (module Runner.Impl)
                unused_external_checks result ~a foreign_field_modulus
            in

            (* Check for expected quantity of external checks *)
            if Field.Constant.(equal a zero) then
              assert (
                Mina_stdlib.List.Length.equal unused_external_checks.bounds 18 )
            else
              assert (
                Mina_stdlib.List.Length.equal unused_external_checks.bounds 20 ) ;
            assert (
              Mina_stdlib.List.Length.equal unused_external_checks.multi_ranges
                8 ) ;
            assert (
              Mina_stdlib.List.Length.equal
                unused_external_checks.compact_multi_ranges 8 ) ;

            (* Check output matches expected result *)
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    result expected_result ) ) ;
            () )
      in

      cs
    in

    let _cs =
      let a = Bignum_bigint.of_int 17 in
      let b = Bignum_bigint.of_int 0 in
      let modulus = Bignum_bigint.of_int 7879 in
      let point = (Bignum_bigint.of_int 1729, Bignum_bigint.of_int 4830) in
      let expected_result =
        (Bignum_bigint.of_int 355, Bignum_bigint.of_int 3132)
      in
      assert (is_on_curve point a b modulus) ;
      assert (is_on_curve expected_result a b modulus) ;
      test_group_double_chained point expected_result ~a modulus
    in

    let point =
      ( Bignum_bigint.of_string
          "42044065574201065781794313442437176970676726666507255383911343977315911214824"
      , Bignum_bigint.of_string
          "31965905005059593108764147692698952070443290622957461138987132030153087962524"
      )
    in
    let expected_result =
      ( Bignum_bigint.of_string
          "25296422933760701668354080561191268087967569090553018544803607419093394376171"
      , Bignum_bigint.of_string
          "8046470730121032635013615006105175410553103561598164661406103935504325838485"
      )
    in

    assert (secp256k1_is_on_curve point) ;
    assert (secp256k1_is_on_curve expected_result) ;

    let _cs =
      test_group_double_chained point expected_result secp256k1_modulus
    in
    () )

let%test_unit "group_ops_mixed" =
  if (* tests_enabled *) false then (
    let open Kimchi_gadgets_test_runner in
    (* Initialize the SRS cache. *)
    let () =
      try Kimchi_pasta.Vesta_based_plonk.Keypair.set_urs_info [] with _ -> ()
    in

    (* Test mix of group operations (e.g. things are wired correctly *)
    let test_group_ops_mixed ?cs
        (left_input : Bignum_bigint.t * Bignum_bigint.t)
        (right_input : Bignum_bigint.t * Bignum_bigint.t)
        (expected_result : Bignum_bigint.t * Bignum_bigint.t)
        ?(a = Bignum_bigint.zero)
        (* curve parameter a *)
          (foreign_field_modulus : Bignum_bigint.t) =
      (* Generate and verify proof *)
      let cs, _proof_keypair, _proof =
        Runner.generate_and_verify_proof ?cs (fun () ->
            let open Runner.Impl in
            let a = Common.bignum_bigint_to_field (module Runner.Impl) a in
            (* Prepare test inputs *)
            let foreign_field_modulus =
              Foreign_field.bignum_bigint_to_field_standard_limbs
                (module Runner.Impl)
                foreign_field_modulus
            in
            let left_input =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                left_input
            in
            let right_input =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                right_input
            in
            let expected_result =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                expected_result
            in

            (* Create external checks context for tracking extra constraints
               that are required for soundness (unused in this simple test) *)
            let unused_external_checks =
              Foreign_field.External_checks.create (module Runner.Impl)
            in

            (* R + L = S *)
            let sum =
              group_add
                (module Runner.Impl)
                unused_external_checks left_input right_input
                foreign_field_modulus
            in

            (* S + S = D *)
            let double =
              group_double
                (module Runner.Impl)
                unused_external_checks sum ~a foreign_field_modulus
            in

            (* Check for expected quantity of external checks *)
            if Field.Constant.(equal a zero) then
              assert (
                Mina_stdlib.List.Length.equal unused_external_checks.bounds 15 )
            else
              assert (
                Mina_stdlib.List.Length.equal unused_external_checks.bounds 16 ) ;
            assert (
              Mina_stdlib.List.Length.equal unused_external_checks.multi_ranges
                7 ) ;
            assert (
              Mina_stdlib.List.Length.equal
                unused_external_checks.compact_multi_ranges 7 ) ;

            (* Check output matches expected result *)
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    double expected_result ) ) ;
            () )
      in

      cs
    in

    let _cs =
      let a = Bignum_bigint.of_int 17 in
      let b = Bignum_bigint.of_int 0 in
      let modulus = Bignum_bigint.of_int 7879 in
      let point1 = (Bignum_bigint.of_int 1729, Bignum_bigint.of_int 4830) in
      let point2 = (Bignum_bigint.of_int 993, Bignum_bigint.of_int 622) in
      let expected_result =
        (Bignum_bigint.of_int 6762, Bignum_bigint.of_int 4635)
      in
      assert (is_on_curve point1 a b modulus) ;
      assert (is_on_curve point2 a b modulus) ;
      assert (is_on_curve expected_result a b modulus) ;

      test_group_ops_mixed point1 point2 expected_result ~a modulus
    in

    let point1 =
      ( Bignum_bigint.of_string
          "37404488720929062958906788322651728322575666040491554170565829193307192693651"
      , Bignum_bigint.of_string
          "9656313713772632982161856264262799630428732532087082991934556488549329780427"
      )
    in
    let point2 =
      ( Bignum_bigint.of_string
          "31293985021118266786561893156019691372812643656725598796588178883202613100468"
      , Bignum_bigint.of_string
          "62519749065576060946018142578164411421793328932510041279923944104940749401503"
      )
    in
    let expected_result =
      ( Bignum_bigint.of_string
          "43046886127279816590953923378970473409794361644471707353489087385548452456295"
      , Bignum_bigint.of_string
          "67554760054687646408788973635096250584575090419180209042279187069048864087921"
      )
    in

    assert (secp256k1_is_on_curve point1) ;
    assert (secp256k1_is_on_curve point2) ;
    assert (secp256k1_is_on_curve expected_result) ;

    let _cs =
      test_group_ops_mixed point1 point2 expected_result secp256k1_modulus
    in
    () )

let%test_unit "group_properties" =
  if (* tests_enabled *) false then (
    let open Kimchi_gadgets_test_runner in
    (* Initialize the SRS cache. *)
    let () =
      try Kimchi_pasta.Vesta_based_plonk.Keypair.set_urs_info [] with _ -> ()
    in

    (* Test group properties *)
    let test_group_properties ?cs (point_a : Bignum_bigint.t * Bignum_bigint.t)
        (point_b : Bignum_bigint.t * Bignum_bigint.t)
        (point_c : Bignum_bigint.t * Bignum_bigint.t)
        (expected_commutative_result : Bignum_bigint.t * Bignum_bigint.t)
        (expected_associative_result : Bignum_bigint.t * Bignum_bigint.t)
        (expected_distributive_result : Bignum_bigint.t * Bignum_bigint.t)
        ?(a = Bignum_bigint.zero) (foreign_field_modulus : Bignum_bigint.t) =
      (* Generate and verify proof *)
      let cs, _proof_keypair, _proof =
        Runner.generate_and_verify_proof ?cs (fun () ->
            let open Runner.Impl in
            (* Prepare test inputs *)
            let a = Common.bignum_bigint_to_field (module Runner.Impl) a in
            let foreign_field_modulus =
              Foreign_field.bignum_bigint_to_field_standard_limbs
                (module Runner.Impl)
                foreign_field_modulus
            in
            let point_a =
              Affine.of_bignum_bigint_coordinates (module Runner.Impl) point_a
            in
            let point_b =
              Affine.of_bignum_bigint_coordinates (module Runner.Impl) point_b
            in
            let point_c =
              Affine.of_bignum_bigint_coordinates (module Runner.Impl) point_c
            in
            let expected_commutative_result =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                expected_commutative_result
            in
            let expected_associative_result =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                expected_associative_result
            in
            let expected_distributive_result =
              Affine.of_bignum_bigint_coordinates
                (module Runner.Impl)
                expected_distributive_result
            in

            (* Create external checks context for tracking extra constraints
               that are required for soundness (unused in this simple test) *)
            let unused_external_checks =
              Foreign_field.External_checks.create (module Runner.Impl)
            in

            (*
             * Commutative property tests
             *
             *     A + B = B + A
             *)
            let a_plus_b =
              (* A + B *)
              group_add
                (module Runner.Impl)
                unused_external_checks point_a point_b foreign_field_modulus
            in

            let b_plus_a =
              (* B + A *)
              group_add
                (module Runner.Impl)
                unused_external_checks point_b point_a foreign_field_modulus
            in

            (* Todo add equality wiring *)
            (* Assert A + B = B + A *)
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover (module Runner.Impl) a_plus_b b_plus_a ) ) ;

            (* Assert A + B = expected_commutative_result *)
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    a_plus_b expected_commutative_result ) ) ;

            (*
             * Associativity property tests
             *
             *     (A + B) + C = A + (B + C)
             *)
            let b_plus_c =
              (* B + C *)
              group_add
                (module Runner.Impl)
                unused_external_checks point_b point_c foreign_field_modulus
            in

            let a_plus_b_plus_c =
              (* (A + B) + C *)
              group_add
                (module Runner.Impl)
                unused_external_checks a_plus_b point_c foreign_field_modulus
            in

            let b_plus_c_plus_a =
              (* A + (B + C) *)
              group_add
                (module Runner.Impl)
                unused_external_checks point_a b_plus_c foreign_field_modulus
            in

            (* Assert (A + B) + C = A + (B + C) *)
            Affine.assert_equal
              (module Runner.Impl)
              a_plus_b_plus_c b_plus_c_plus_a ;
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    a_plus_b_plus_c b_plus_c_plus_a ) ) ;

            (* Assert A + B = expected_commutative_result *)
            Affine.assert_equal
              (module Runner.Impl)
              a_plus_b_plus_c expected_associative_result ;
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    a_plus_b_plus_c expected_associative_result ) ) ;

            (*
             * Distributive property tests
             *
             *     2 * (A + B) = 2 * A + 2 * B
             *)
            let double_of_sum =
              (* 2 * (A + B) *)
              group_double
                (module Runner.Impl)
                unused_external_checks a_plus_b ~a foreign_field_modulus
            in

            let double_a =
              (* 2 * A *)
              group_double
                (module Runner.Impl)
                unused_external_checks point_a ~a foreign_field_modulus
            in

            let double_b =
              (* 2 * B *)
              group_double
                (module Runner.Impl)
                unused_external_checks point_b ~a foreign_field_modulus
            in

            let sum_of_doubles =
              (* 2 * A + 2 * B *)
              group_add
                (module Runner.Impl)
                unused_external_checks double_a double_b foreign_field_modulus
            in

            (* Assert 2 * (A + B) = 2 * A + 2 * B *)
            Affine.assert_equal
              (module Runner.Impl)
              double_of_sum sum_of_doubles ;
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    double_of_sum sum_of_doubles ) ) ;

            (* Assert 2 * (A + B) = expected_distributive_result *)
            Affine.assert_equal
              (module Runner.Impl)
              double_of_sum expected_distributive_result ;
            as_prover (fun () ->
                assert (
                  Affine.equal_as_prover
                    (module Runner.Impl)
                    double_of_sum expected_distributive_result ) ) ;
            () )
      in

      cs
    in

    (* Test with secp256k1 curve *)
    let point_a =
      ( Bignum_bigint.of_string
          "104139740379639537914620141697889522643195068624996157573145175343741564772195"
      , Bignum_bigint.of_string
          "24686993868898088086788882517246409097753788695591891584026176923146938009248"
      )
    in
    let point_b =
      ( Bignum_bigint.of_string
          "36743784007303620043843440776745227903854397846775577839885696093428264537689"
      , Bignum_bigint.of_string
          "37572687997781202307536515813734773072395389211771147301250986255900442183367"
      )
    in
    let point_c =
      ( Bignum_bigint.of_string
          "49696436312078070273833592624394555921078337653960324106519507173094660966846"
      , Bignum_bigint.of_string
          "8233980127281521579593600770666525234073102501648621450313070670075221490597"
      )
    in
    let expected_commutative_result =
      (* A + B *)
      ( Bignum_bigint.of_string
          "82115184826944281192212047494549730220285137025844635077989275753462094545317"
      , Bignum_bigint.of_string
          "65806312870411158102677100909644698935674071740730856487954465264167266803940"
      )
    in
    let expected_associative_result =
      (* A + B + C *)
      ( Bignum_bigint.of_string
          "32754193298666340516904674847278729692077935996237244820399615298932008086168"
      , Bignum_bigint.of_string
          "98091569220567533408383096211571578494419313923145170353903484742714309353581"
      )
    in
    (* 2* (A + B) *)
    let expected_distributive_result =
      ( Bignum_bigint.of_string
          "92833221040863134022467437260311951512477869225271942781021131905899386232859"
      , Bignum_bigint.of_string
          "88875130971526456079808346479572776785614636860343295137331156710761285100759"
      )
    in

    assert (secp256k1_is_on_curve point_a) ;
    assert (secp256k1_is_on_curve point_b) ;
    assert (secp256k1_is_on_curve point_c) ;
    assert (secp256k1_is_on_curve expected_commutative_result) ;
    assert (secp256k1_is_on_curve expected_associative_result) ;
    assert (secp256k1_is_on_curve expected_distributive_result) ;

    let _cs =
      test_group_properties point_a point_b point_c expected_commutative_result
        expected_associative_result expected_distributive_result
        secp256k1_modulus
    in

    (*
     * Test with NIST P-224 curve
     *     y^2 = x^3 -3 * x + 18958286285566608000408668544493926415504680968679321075787234672564
     *)
    let p224_modulus =
      Bignum_bigint.of_string
        "0xffffffffffffffffffffffffffffffff000000000000000000000001"
    in
    let a_param =
      (* - 3 *)
      Bignum_bigint.of_string
        "0xfffffffffffffffffffffffffffffffefffffffffffffffffffffffe"
      (* Note: p224 a_param < vesta_modulus *)
    in
    let b_param =
      (* 18958286285566608000408668544493926415504680968679321075787234672564 *)
      Bignum_bigint.of_string
        "0xb4050a850c04b3abf54132565044b0b7d7bfd8ba270b39432355ffb4"
    in

    let point_a =
      ( Bignum_bigint.of_string
          "20564182195513988720077877094445678909500371329094056390559170498601"
      , Bignum_bigint.of_string
          "2677931089606376366731934050370502738338362171950142296573730478996"
      )
    in
    let point_b =
      ( Bignum_bigint.of_string
          "15331822097908430690332647239357533892026967275700588538504771910797"
      , Bignum_bigint.of_string
          "4049755097518382314285232898392449281690500011901831745754040069555"
      )
    in
    let point_c =
      ( Bignum_bigint.of_string
          "25082387259758106010480779115787834869202362152205819097823199674591"
      , Bignum_bigint.of_string
          "5836788343546154757468239805956174785568118741436223437725908467573"
      )
    in
    let expected_commutative_result =
      (* A + B *)
      ( Bignum_bigint.of_string
          "7995206472745921825893910722935139765985673196416788824369950333191"
      , Bignum_bigint.of_string
          "8265737252928447574971649463676620963677557474048291412774437728538"
      )
    in
    let expected_associative_result =
      (* A + B + C *)
      ( Bignum_bigint.of_string
          "3257699169520051230744895047894307554057883749899622226174209882724"
      , Bignum_bigint.of_string
          "7231957109409135332430424812410043083405298563323557216003172539215"
      )
    in
    (* 2 * (A + B) *)
    let expected_distributive_result =
      ( Bignum_bigint.of_string
          "12648120179660537445264809843313333879121180184951710403373354501995"
      , Bignum_bigint.of_string
          "130351274476047354152272911484022089680853927680837325730785745821"
      )
    in
    assert (is_on_curve point_a a_param b_param p224_modulus) ;
    assert (is_on_curve point_b a_param b_param p224_modulus) ;
    assert (is_on_curve point_c a_param b_param p224_modulus) ;
    assert (is_on_curve expected_commutative_result a_param b_param p224_modulus) ;
    assert (is_on_curve expected_associative_result a_param b_param p224_modulus) ;
    assert (
      is_on_curve expected_distributive_result a_param b_param p224_modulus ) ;

    let _cs =
      test_group_properties point_a point_b point_c expected_commutative_result
        expected_associative_result expected_distributive_result ~a:a_param
        p224_modulus
    in

    (*
     * Test with bn254 curve
     *     y^2 = x^3 + 0 * x + 2
     *)
    let bn254_modulus =
      Bignum_bigint.of_string
        "16798108731015832284940804142231733909889187121439069848933715426072753864723"
    in
    let a_param = Bignum_bigint.of_int 0 in
    let b_param = Bignum_bigint.of_int 2 in

    let point_a =
      ( Bignum_bigint.of_string
          "7489139758950854827551487063927077939563321761044181276420624792983052878185"
      , Bignum_bigint.of_string
          "2141496180075348025061594016907544139242551437114964865155737156269728330559"
      )
    in
    let point_b =
      ( Bignum_bigint.of_string
          "9956514278304933003335636627606783773825106169180128855351756770342193930117"
      , Bignum_bigint.of_string
          "1762095167736644705377345502398082775379271270251951679097189107067141702434"
      )
    in
    let point_c =
      ( Bignum_bigint.of_string
          "15979993511612396332695593711346186397534040520881664680241489873512193259980"
      , Bignum_bigint.of_string
          "10163302455117602785156120251106605625181898385895334763785764107729313787391"
      )
    in
    let expected_commutative_result =
      (* A + B *)
      ( Bignum_bigint.of_string
          "13759678784866515747881317697821131633872329198354290325517257690138811932261"
      , Bignum_bigint.of_string
          "4040037229868341675068324615541961445935091050207890024311587166409180676332"
      )
    in
    let expected_associative_result =
      (* A + B + C *)
      ( Bignum_bigint.of_string
          "16098676871974911854784905872738346730775870232298829667865365025475731380192"
      , Bignum_bigint.of_string
          "12574401007382321193248731381385712204251317924015127170657534965607164101869"
      )
    in
    (* 2 * (A + B) *)
    let expected_distributive_result =
      ( Bignum_bigint.of_string
          "9395314037281443688092936149000099903064729021023078772338895863158377429106"
      , Bignum_bigint.of_string
          "14218226539011623427628171089944499674924086623747284955166459983416867234215"
      )
    in
    assert (is_on_curve point_a a_param b_param bn254_modulus) ;
    assert (is_on_curve point_b a_param b_param bn254_modulus) ;
    assert (is_on_curve point_c a_param b_param bn254_modulus) ;
    assert (
      is_on_curve expected_commutative_result a_param b_param bn254_modulus ) ;
    assert (
      is_on_curve expected_associative_result a_param b_param bn254_modulus ) ;
    assert (
      is_on_curve expected_distributive_result a_param b_param bn254_modulus ) ;

    let _cs =
      test_group_properties point_a point_b point_c expected_commutative_result
        expected_associative_result expected_distributive_result ~a:a_param
        bn254_modulus
    in

    (*
     * Test with (Pasta) Pallas curve (on Vesta native)
     *     y^2 = x^3 + 5
     *)
    let pallas_modulus =
      Bignum_bigint.of_string
        "28948022309329048855892746252171976963363056481941560715954676764349967630337"
    in
    let a_param = Bignum_bigint.of_int 0 in
    let b_param = Bignum_bigint.of_int 5 in

    let point_a =
      ( Bignum_bigint.of_string
          "3687554385661875988153708668118568350801595287403286241588941623974773451174"
      , Bignum_bigint.of_string
          "4125300560830971348224390975663473429075828688503632065713036496032796088150"
      )
    in
    let point_b =
      ( Bignum_bigint.of_string
          "13150688393980970390008393861087383374732464068960495642594966124646063172404"
      , Bignum_bigint.of_string
          "2084472543720136255281934655991399553143524556330848293815942786297013884533"
      )
    in
    let point_c =
      ( Bignum_bigint.of_string
          "26740989696982304482414554371640280045791606641637898228291292575942109454805"
      , Bignum_bigint.of_string
          "14906024627800344780747375705291059367428823794643427263104879621768813059138"
      )
    in
    let expected_commutative_result =
      (* A + B *)
      ( Bignum_bigint.of_string
          "11878681988771676869370724830611253729756170947285460876552168044614948225457"
      , Bignum_bigint.of_string
          "14497133356854845193720136968564933709713968802446650329644811738138289288792"
      )
    in
    let expected_associative_result =
      (* A + B + C *)
      ( Bignum_bigint.of_string
          "8988194870545558903676114324437227470798902472195505563098874771184576333284"
      , Bignum_bigint.of_string
          "2715074574400479059415686517976976756653616385004805753779147804207672517454"
      )
    in
    (* 2 * (A + B) *)
    let expected_distributive_result =
      ( Bignum_bigint.of_string
          "5858337972845412034234591451268195730728808894992644330419904703508222498795"
      , Bignum_bigint.of_string
          "7758708768756582293117808728373210197717986974150537098853332332749930840785"
      )
    in
    assert (is_on_curve point_a a_param b_param pallas_modulus) ;
    assert (is_on_curve point_b a_param b_param pallas_modulus) ;
    assert (is_on_curve point_c a_param b_param pallas_modulus) ;
    assert (
      is_on_curve expected_commutative_result a_param b_param pallas_modulus ) ;
    assert (
      is_on_curve expected_associative_result a_param b_param pallas_modulus ) ;
    assert (
      is_on_curve expected_distributive_result a_param b_param pallas_modulus ) ;

    let _cs =
      test_group_properties point_a point_b point_c expected_commutative_result
        expected_associative_result expected_distributive_result ~a:a_param
        pallas_modulus
    in

    () )
