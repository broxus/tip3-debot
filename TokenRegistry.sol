pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;


contract TokenRegistry {
    uint256 owner;
    address[] public tokens;

    constructor(address[] _tokens) public {
        tvm.accept();

        owner = msg.pubkey();
        tokens = _tokens;
    }

    function setTokens(address[] new_tokens) public {
        require (msg.pubkey() == owner, 20000);
        tvm.accept();

        tokens = new_tokens;
    }
}
