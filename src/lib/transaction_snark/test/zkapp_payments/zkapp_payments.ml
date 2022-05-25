open Core
open Mina_ledger
open Currency
open Snark_params
open Tick
module U = Transaction_snark_tests.Util
module Spec = Transaction_snark.For_tests.Spec
open Mina_base

let%test_module "Zkapp payments tests" =
  ( module struct
    let memo = Signed_command_memo.create_from_string_exn "Zkapp payments tests"

    let constraint_constants = U.constraint_constants

    let merkle_root_after_parties_exn t ~txn_state_view txn =
      let hash =
        Ledger.merkle_root_after_parties_exn
          ~constraint_constants:U.constraint_constants ~txn_state_view t txn
      in
      Frozen_ledger_hash.of_ledger_hash hash

    let signed_signed ~(wallets : U.Wallet.t array) i j : Parties.t =
      let full_amount = 8_000_000_000 in
      let fee = Fee.of_int (Random.int full_amount) in
      let receiver_amount =
        Amount.sub (Amount.of_int full_amount) (Amount.of_fee fee)
        |> Option.value_exn
      in
      let acct1 = wallets.(i) in
      let acct2 = wallets.(j) in
      let new_state : _ Zkapp_state.V.t =
        Pickles_types.Vector.init Zkapp_state.Max_state_size.n ~f:Field.of_int
      in
      Parties.of_wire
        { fee_payer =
            { body =
                { public_key = acct1.account.public_key
                ; update =
                    { app_state =
                        Pickles_types.Vector.map new_state ~f:(fun x ->
                            Zkapp_basic.Set_or_keep.Set x )
                    ; delegate = Keep
                    ; verification_key = Keep
                    ; permissions = Keep
                    ; zkapp_uri = Keep
                    ; token_symbol = Keep
                    ; timing = Keep
                    ; voting_for = Keep
                    }
                ; fee = Fee.of_int full_amount
                ; events = []
                ; sequence_events = []
                ; protocol_state_precondition =
                    Zkapp_precondition.Protocol_state.accept
                ; nonce = acct1.account.nonce
                }
            ; authorization = Signature.dummy
            }
        ; other_parties =
            [ { body =
                  { public_key = acct1.account.public_key
                  ; update = Party.Update.noop
                  ; token_id = Token_id.default
                  ; balance_change =
                      Amount.Signed.(of_unsigned receiver_amount |> negate)
                  ; increment_nonce = true
                  ; events = []
                  ; sequence_events = []
                  ; call_data = Field.zero
                  ; call_depth = 0
                  ; protocol_state_precondition =
                      Zkapp_precondition.Protocol_state.accept
                  ; use_full_commitment = false
                  ; account_precondition = Accept
                  ; caller = Call
                  }
              ; authorization = Signature Signature.dummy
              }
            ; { body =
                  { public_key = acct2.account.public_key
                  ; update = Party.Update.noop
                  ; token_id = Token_id.default
                  ; balance_change = Amount.Signed.(of_unsigned receiver_amount)
                  ; increment_nonce = false
                  ; events = []
                  ; sequence_events = []
                  ; call_data = Field.zero
                  ; call_depth = 0
                  ; protocol_state_precondition =
                      Zkapp_precondition.Protocol_state.accept
                  ; use_full_commitment = false
                  ; account_precondition = Accept
                  ; caller = Call
                  }
              ; authorization = None_given
              }
            ]
        ; memo
        }

    let%test_unit "merkle_root_after_zkapp_command_exn_immutable" =
      Test_util.with_randomness 123456789 (fun () ->
          let wallets = U.Wallet.random_wallets () in
          Ledger.with_ledger ~depth:U.ledger_depth ~f:(fun ledger ->
              Array.iter
                (Array.sub wallets ~pos:1 ~len:(Array.length wallets - 1))
                ~f:(fun { account; private_key = _ } ->
                  Ledger.create_new_account_exn ledger
                    (Account.identifier account)
                    account ) ;
              let t1 =
                let i, j = (1, 2) in
                signed_signed ~wallets i j
              in
              let hash_pre = Ledger.merkle_root ledger in
              let _target =
                let txn_state_view =
                  Mina_state.Protocol_state.Body.view U.genesis_state_body
                in
                merkle_root_after_parties_exn ledger ~txn_state_view t1
              in
              let hash_post = Ledger.merkle_root ledger in
              [%test_eq: Field.t] hash_pre hash_post ) )

    let%test_unit "zkapps-based payment" =
      let open Mina_transaction_logic.For_tests in
      Quickcheck.test ~trials:2 Test_spec.gen ~f:(fun { init_ledger; specs } ->
          Ledger.with_ledger ~depth:U.ledger_depth ~f:(fun ledger ->
              let parties =
                party_send ~constraint_constants (List.hd_exn specs)
              in
              Init_ledger.init (module Ledger.Ledger_inner) init_ledger ledger ;
              U.apply_parties ledger [ parties ] )
          |> fun _ -> () )

    let%test_unit "Consecutive zkapps-based payments" =
      let open Mina_transaction_logic.For_tests in
      Quickcheck.test ~trials:2 Test_spec.gen ~f:(fun { init_ledger; specs } ->
          Ledger.with_ledger ~depth:U.ledger_depth ~f:(fun ledger ->
              let partiess =
                List.map
                  ~f:(fun s ->
                    let use_full_commitment =
                      Quickcheck.random_value Bool.quickcheck_generator
                    in
                    party_send ~constraint_constants ~use_full_commitment s )
                  specs
              in
              Init_ledger.init (module Ledger.Ledger_inner) init_ledger ledger ;
              U.apply_parties ledger partiess |> fun _ -> () ) )

    let%test_unit "multiple transfers from one account" =
      let open Mina_transaction_logic.For_tests in
      Quickcheck.test ~trials:1 U.gen_snapp_ledger
        ~f:(fun ({ init_ledger; specs }, new_kp) ->
          Ledger.with_ledger ~depth:U.ledger_depth ~f:(fun ledger ->
              Async.Thread_safe.block_on_async_exn (fun () ->
                  let fee = Fee.of_int 1_000_000 in
                  let amount = Amount.of_int 1_000_000_000 in
                  let spec = List.hd_exn specs in
                  let receiver_count = 3 in
                  let total_amount =
                    Amount.scale amount receiver_count |> Option.value_exn
                  in
                  let new_receiver =
                    Signature_lib.Public_key.compress new_kp.public_key
                  in
                  let new_receiver_amount =
                    Option.value_exn
                      (Amount.sub amount
                         (Amount.of_fee
                            constraint_constants.account_creation_fee ) )
                  in
                  let test_spec : Spec.t =
                    { sender = spec.sender
                    ; fee
                    ; fee_payer = None
                    ; receivers =
                        (new_receiver, new_receiver_amount)
                        :: ( List.take specs (receiver_count - 1)
                           |> List.map ~f:(fun s -> (s.receiver, amount)) )
                    ; amount = total_amount
                    ; zkapp_account_keypairs = []
                    ; memo
                    ; new_zkapp_account = false
                    ; snapp_update = Party.Update.dummy
                    ; current_auth = Permissions.Auth_required.Signature
                    ; call_data = Snark_params.Tick.Field.zero
                    ; events = []
                    ; sequence_events = []
                    ; protocol_state_precondition = None
                    ; account_precondition = None
                    }
                  in
                  let parties =
                    Transaction_snark.For_tests.multiple_transfers test_spec
                  in
                  Init_ledger.init
                    (module Ledger.Ledger_inner)
                    init_ledger ledger ;
                  U.check_parties_with_merges_exn ledger [ parties ] ) ) )

    let%test_unit "zkapps payments failed due to insufficient funds" =
      let open Mina_transaction_logic.For_tests in
      Quickcheck.test ~trials:5 U.gen_snapp_ledger
        ~f:(fun ({ init_ledger; specs }, new_kp) ->
          Ledger.with_ledger ~depth:U.ledger_depth ~f:(fun ledger ->
              Async.Thread_safe.block_on_async_exn (fun () ->
                  Init_ledger.init
                    (module Ledger.Ledger_inner)
                    init_ledger ledger ;
                  let fee = Fee.of_int 1_000_000 in
                  let spec = List.hd_exn specs in
                  let sender_pk =
                    (fst spec.sender).public_key
                    |> Signature_lib.Public_key.compress
                  in
                  let sender_id : Account_id.t =
                    Account_id.create sender_pk Token_id.default
                  in
                  let sender_location =
                    Ledger.location_of_account ledger sender_id
                    |> Option.value_exn
                  in
                  let sender_account =
                    Ledger.get ledger sender_location |> Option.value_exn
                  in
                  let sender_balance = sender_account.balance in
                  let amount =
                    Amount.add
                      Balance.(to_amount sender_balance)
                      Amount.(of_int 1_000_000)
                    |> Option.value_exn
                  in
                  let receiver_count = 3 in
                  let total_amount =
                    Amount.scale amount receiver_count |> Option.value_exn
                  in
                  let new_receiver =
                    Signature_lib.Public_key.compress new_kp.public_key
                  in
                  let test_spec : Spec.t =
                    { sender = spec.sender
                    ; fee
                    ; fee_payer = None
                    ; receivers =
                        (new_receiver, amount)
                        :: ( List.take specs (receiver_count - 1)
                           |> List.map ~f:(fun s -> (s.receiver, amount)) )
                    ; amount = total_amount
                    ; zkapp_account_keypairs = []
                    ; memo
                    ; new_zkapp_account = false
                    ; snapp_update = Party.Update.dummy
                    ; current_auth = Permissions.Auth_required.Signature
                    ; call_data = Snark_params.Tick.Field.zero
                    ; events = []
                    ; sequence_events = []
                    ; protocol_state_precondition = None
                    ; account_precondition = None
                    }
                  in
                  let parties =
                    Transaction_snark.For_tests.multiple_transfers test_spec
                  in
                  U.check_parties_with_merges_exn
                    ~expected_failure:Transaction_status.Failure.Overflow ledger
                    [ parties ] ) ) )
  end )
