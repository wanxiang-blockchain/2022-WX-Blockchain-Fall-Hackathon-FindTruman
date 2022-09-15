type metadataParams is big_map(string, bytes)

type token_id is nat;

type balance_of_request is [@layout:comb] record [
  owner: address;
  token_id: token_id;
]

type balance_of_response is [@layout:comb] record [
  request: balance_of_request;
  balance: nat;
]

type balance_of_params is [@layout:comb] record [
  requests: list(balance_of_request);
  callback: contract (list(balance_of_response));
]

type transfer_destination is [@layout:comb] record [
  to_: address;
  token_id: token_id;
  amount: nat;
]

type transfer_type is [@layout:comb] record [
  from_: address;
  txs: list (transfer_destination);
]

type transfer_param_type is list (transfer_type)

type update_operator_action_params_type is [@layout:comb] record [
  owner : address;
  operator : address;
  token_id: nat;
]

type update_operator_action_type is [@layout:comb]
  | Add_operator of update_operator_action_params_type
  | Remove_operator of update_operator_action_params_type

type update_operator_params is list (update_operator_action_type)

type token_metadata_value is record [
  token_id: token_id;
  token_info: map(string, bytes)
]

const noOperations: list (operation) = nil;

type ledger_key is [@layout:comb] record [
  owner: address;
  token_id: token_id
];

type tokenMetadataParams is [@layout:comb] record [
  metadata: map (string, bytes);
  owner: address;
  token_id: token_id
]

type storage is [@layout:comb] record [
  admin: address;
  paused: bool;
  nextTokenId: nat;
  ledger: big_map(ledger_key, nat);
  operators: big_map(update_operator_action_params_type, unit);
  token_metadata: big_map(nat, token_metadata_value);
  metadata: big_map(string, bytes)
]

const initial_storage = record [
  admin = ("tz1citGpMgkQrJSXuwy9JFPUS6ETDCRJBW7j": address);
  paused = false;
  nextTokenId = 70000n;
  ledger = (big_map []: big_map(ledger_key, nat));
  operators = (big_map []: big_map(update_operator_action_params_type, unit));
  token_metadata = (big_map []: big_map(nat, token_metadata_value));
  metadata = (big_map []: big_map(string, bytes))
]

type return is list (operation) * storage;

type auroraAction is
  | SetMetadata of metadataParams
  | AddTokenMetadata of tokenMetadataParams
  | UpdateAdmin of address
  | Update_operators of update_operator_params
  | Transfer of transfer_param_type
  | Balance_of of balance_of_params
  | Pause of unit
  | Unpause of unit

[@inline] function get_balance(const params: ledger_key; const s: storage): nat is
  case s.ledger[params] of [
    | None -> 0n
    | Some(param) -> param
  ]

[@inline] function iterate_transfer(var s: storage; const param: transfer_type): storage is {

  // local variables
  const sender = Tezos.get_sender();

  const from_: address = param.from_;
  function make_transfer(var s: storage; const tx: transfer_destination): storage is
    begin
      assert_with_error(from_ = sender or Big_map.mem(record[owner = from_; operator = sender; token_id = tx.token_id], s.operators), "FA2_NOT_OPERATOR");
      const from_key = record[
        owner = from_;
        token_id = tx.token_id
      ];
      const to_key = record[
        owner = tx.to_;
        token_id = tx.token_id
      ];
      var sender_balance: nat := get_balance(record[owner = from_; token_id = tx.token_id], s);
      if sender_balance < tx.amount then failwith("FA2_INSUFFICIENT_BALANCE");
      if (from_ = tx.to_) or (tx.amount = 0n) then skip else {
        const dest_balance: nat = get_balance(to_key, s);
        s.ledger[from_key] := abs(sender_balance - tx.amount);
        if s.ledger[from_key] = Some(0n) then s.ledger := Big_map.remove(from_key, s.ledger);
        s.ledger[to_key] := dest_balance + tx.amount;
      };
    end with s;
} with (List.fold(make_transfer, param.txs, s))

function fa2_transfer(const p: transfer_param_type; var s: storage): return is
   (noOperations, List.fold(iterate_transfer, p, s))

function fa2_balance_of(const params: balance_of_params; const s: storage): return is
  begin
    function get_balance_response (const r: balance_of_request): balance_of_response is
      record[
        balance = get_balance(record [owner = r.owner; token_id = r.token_id], s);
        request = r
      ];
  end with (list [Tezos.transaction(List.map(get_balance_response, params.requests), 0mutez, params.callback)], s)

function update_operator (var s: storage; const action: update_operator_action_type): storage is {
  case action of [
    | Add_operator(param) -> {
      if Tezos.get_sender() =/= param.owner then failwith("FA2_NOT_OWNER")
      else s.operators := Big_map.add(record [owner = param.owner; operator = param.operator; token_id = param.token_id], unit, s.operators);
    }
    | Remove_operator(param) -> {
      if Tezos.get_sender() =/= param.owner then failwith("FA2_NOT_OWNER")
      else s.operators := Big_map.remove(record [owner = param.owner; operator = param.operator; token_id = param.token_id], s.operators);
    }
  ];
 } with s;

function updateAdmin(const new_admin: address; var s: storage): storage is {
  if Tezos.get_amount() > 0mutez then failwith("dont send tez");
  if Tezos.get_sender() =/= s.admin then failwith("access denied");
    s.admin := new_admin;
} with s;

function fa2_update_operators(const params: update_operator_params; var s: storage): return is
(noOperations, List.fold(update_operator, params, s))

[@inline] function setMetadata(const params: metadataParams; var s: storage): storage is {
  if Tezos.get_amount() > 0mutez then failwith("dont send tez");
  if Tezos.get_sender() =/= s.admin then failwith("access denied");
  s.metadata := params;
} with s;

type auroraAction is
  | SetMetadata of metadataParams
  | AddTokenMetadata of tokenMetadataParams
  | UpdateAdmin of address
  | Update_operators of update_operator_params
  | Transfer of transfer_param_type
  | Balance_of of balance_of_params
  | Pause of unit
  | Unpause of unit

function pause(const _params: unit; var s: storage): storage is {
  if Tezos.get_sender() =/= s.admin then failwith("access denied");
  if Tezos.get_amount() > 0mutez then failwith("dont send tez");
  if s.paused then failwith("FA2_ALREADY_PAUSED");
  s.paused := True;
} with s

function unpause(const _params: unit; var s: storage): storage is {
  if Tezos.get_sender() =/= s.admin then failwith("access denied");
  if Tezos.get_amount() > 0mutez then failwith("dont send tez");
  if not s.paused then failwith("FA2_ALREADY_UNPAUSED");
  s.paused := False;
} with s

[@inline] function addTokenMetadata(const params: tokenMetadataParams; var s: storage): storage is {
  if Tezos.get_amount() > 0mutez then failwith("dont send tez");
  
  // create new nft token
  const new_nft: token_metadata_value = record [
    token_id = s.nextTokenId;
    token_info = params.metadata
  ];
  const new_ledger: ledger_key = record [
    owner = params.owner;
    token_id = s.nextTokenId
  ];

  s.token_metadata := Big_map.add(s.nextTokenId, new_nft, s.token_metadata);
  s.ledger := Big_map.add(new_ledger, s.nextTokenId, s.ledger);
  s.nextTokenId := s.nextTokenId + abs(1);

} with s;

function main(const action: auroraAction; const s: storage): return is
  case action of [

    // metadata.ligo
    | SetMetadata(params) -> (noOperations, setMetadata(params, s))

    // token_metadata.ligo
    | AddTokenMetadata(params) -> (noOperations, addTokenMetadata(params, s))

    // admin.ligo
    | UpdateAdmin(params) -> (noOperations, updateAdmin(params, s))

    // fa2.ligo
    | Update_operators(params) -> fa2_update_operators(params, s)
    | Balance_of(params) -> fa2_balance_of(params, s)
    | Transfer(params) -> fa2_transfer(params, s)

    // pause.ligo
    | Pause(params) -> (noOperations, pause(params, s))
    | Unpause(params) -> (noOperations, unpause(params, s))
  ]
