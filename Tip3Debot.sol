pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import "base/Debot.sol";
import "base/Terminal.sol";
import "base/AddressInput.sol";
import "base/Sdk.sol";
import "base/Menu.sol";
import "base/Upgradable.sol";
import "base/Transferable.sol";


interface IRootToken {
    struct rootTokenContractDetails {
        bytes name;
        bytes symbol;
        uint8 decimals;
        TvmCell wallet_code;
        uint256 root_public_key;
        address root_owner_address;
        uint128 total_supply;
        uint128 start_gas_balance;
        bool paused;
    }

    function name() external returns (bytes);
    function symbol() external returns (bytes);
    function decimals() external returns (uint8);
    function total_supply() external returns (uint128);
    function getWalletAddress(uint256 wallet_public_key_, address owner_address_) external returns (address);
    function getDetails() external view returns (rootTokenContractDetails);
}

interface ITokenWallet {
    function balance() external returns (uint128);
    function transferToRecipient(
        uint256 recipient_public_key,
        address recipient_address,
        uint128 tokens,
        uint128 deploy_grams,
        uint128 transfer_grams
    ) external;
}

interface IUserWallet {
    function submitTransaction(
        address payable dest,
        uint128 value,
        bool bounce,
        bool allBalance,
        TvmCell payload
    ) external returns (uint64 transId);
}

interface ITokenRegistry {
    function tokens() external returns (address[]);
}


contract Tip3Debot is Debot, Upgradable, Transferable {
    struct rootTokenContractDetails {
        bytes name;
        bytes symbol;
        uint8 decimals;
        TvmCell wallet_code;
        uint256 root_public_key;
        address root_owner_address;
        uint128 total_supply;
        uint128 start_gas_balance;
        bool paused;
    }

    address public token_registry;

    address[] tokens_list;
    rootTokenContractDetails[] tokens_details;
    uint256 cur_token_id;
    uint256 selected_token_id;

    // user data
    address wallet_address;
    uint256 public_key;

    address token_wallet_address;
    uint128 token_wallet_balance;

    string str_amount_to_send;
    uint128 amount_to_send;

    // receiver
    address receiver_wallet_address;
    uint256 receiver_public_key;


    // token metadata
    uint128 total_supply;
    uint256 token_decimals;
    bytes token_name;
    bytes token_symbol;

    constructor(string debotAbi, address _token_registry) public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        init(DEBOT_ABI, debotAbi, "", address(0));
        token_registry = _token_registry;
    }

    function getRequiredInterfaces() public returns (uint256[] interfaces) {
        return [Menu.ID, Terminal.ID, AddressInput.ID];
	}

    function start() public override {
        Menu.select("Main menu", "Hello, i'm a broxus TIP3 debot. I can help you transfer your TIP3 tokens.", [
            MenuItem("Select TIP3 token", "", tvm.functionId(selectTip3Token)),
            MenuItem("Exit", "", 0)
        ]);
    }

    function fetch() public override returns (Context[] contexts) {}

    function quit() public override {}

    function getVersion() public override returns (string name, uint24 semver) {
        (name, semver) = ("Tip3 token Debot", 1 << 16);
    }

    function selectTip3Token(uint32 index) public {
        Terminal.print(0, "Querying token registry...");
        queryTokenRegistry();
	}

    function showTokensMenu() public {
        MenuItem[] items;

        for (uint i = 0; i < tokens_details.length; i++) {
            rootTokenContractDetails _details = tokens_details[i];
            items.push(MenuItem(_details.symbol, "", tvm.functionId(selectToken)));
        }

        items.push(MenuItem("Exit", "", 0));

        Menu.select("Token menu", "Select token from list below:", items);
    }

    function selectToken(uint32 index) public {
        selected_token_id = index;
        rootTokenContractDetails _details = tokens_details[index];

        Terminal.print(0, format("Name - {}\nDecimals - {}\nTotal supply - {}", _details.name, _details.decimals, _details.total_supply));

        getSenderWalletAddress();
    }

    function getSenderWalletAddress() public {
        Terminal.print(0, "Now enter your Surf wallet address");
        AddressInput.select(tvm.functionId(checkSenderWalletAddress));
    }

    function checkSenderWalletAddress(address value) public {
        wallet_address = value;
        queryTokenWalletAddress();
    }

    // called from queryTokenWalletBalance callback
    function getAmountToSend() public {
        Terminal.inputStr(tvm.functionId(getInputAmount), "Enter amount you want to send. Example: 123 or 123.11", false);
    }

    function getInputAmount(string value) public {
        str_amount_to_send = value;
        uint8 sep_id = findSeparator(value, ".");

        uint256 result; bool status; uint8 decimals = tokens_details[selected_token_id].decimals;
        if (sep_id == 0) {
            // no separator found
            (result, status) = stoi(value);
            // add decimals
            result = result * 10 ** uint256(decimals);
        } else {
            // found separator, add decimals to real and int parts and sum them
            string str_real_part = value.substr(sep_id + 1, value.byteLength() - (sep_id + 1));
            string str_int_part = value.substr(0, sep_id);

            // convert int part
            (uint256 int_part, bool st) = stoi(str_int_part);
            // convert real part
            uint256 real_part_with_decimals = parseRealPart(str_real_part);

            result = int_part * 10 ** uint256(decimals) + real_part_with_decimals;
        }

        amount_to_send = uint128(result);
        string str = format(
            "You entered {}, which is {} according to token decimals ({})",
            value, amount_to_send, decimals
        );
        Terminal.print(0, str);

        getReceiverAddress();
    }

    function findSeparator(string str_num, string sep) internal returns (uint8 sep_id) {
        for (uint8 i = 0; i < str_num.byteLength(); i++) {
            if (str_num.substr(i, 1) == sep) {
                sep_id = i;
            }
        }
    }

    function parseRealPart(string real_part) internal returns (uint256) {
        // lets day we got 1.0012 in token with 6 decimals, so that
        // real_part -> 0012
        // decimals  -> 6
        uint8 decimals = tokens_details[selected_token_id].decimals;
        uint8 power = uint8(decimals) - real_part.byteLength();
        (uint256 result, bool st) = stoi(real_part);
        // result = 12 * 10**2
        return result * 10 ** uint256(power);
    }

    function getReceiverAddress() public {
        Terminal.print(0, "Now enter receiver wallet address");
        AddressInput.select(tvm.functionId(checkWalletAddressReceiver));
    }

    function checkWalletAddressReceiver(address value) public {
        receiver_wallet_address = value;
        finalize();
    }

    function checkPublicKeyReceiver(string value) public {
        (uint256 res, bool st) = stoi(value);

        receiver_public_key = res;
        finalize();
    }

    function finalize() public {
        string final_msg = format("You want to transfer {} ({}) {} tokens to ", str_amount_to_send, amount_to_send, token_symbol);
        if (receiver_public_key > 0) {
            final_msg.append(format("{}", receiver_public_key));
        } else {
            final_msg.append(format("{}", receiver_wallet_address));
        }
        Terminal.print(0, final_msg);

        Terminal.inputBoolean(tvm.functionId(submit), "Submit transaction?");
    }

    function submit(bool value) public {
        if (!value) {
            Terminal.print(0, "Ok, maybe next time. Bye!");
            return;
        }

        optional(uint256) pubkey = 0;

        TvmCell body = tvm.encodeBody(ITokenWallet.transferToRecipient, receiver_public_key, receiver_wallet_address, amount_to_send, uint128(50000000), uint128(0));

        IUserWallet(wallet_address).submitTransaction{
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: pubkey,
                time: uint64(now),
                expire: 0,
                callbackId: tvm.functionId(success),
                onErrorId: 0
        }(token_wallet_address, uint128(500000000), true, false, body);

    }

    // --------------------------- QUERY FUNCTIONS -------------------------------------
    function queryTokenRegistry() public view {
        optional(uint256) pubkey;
        ITokenRegistry(token_registry).tokens{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setTokens),
            onErrorId: 0
        }();
    }

    function queryTokenDetails(uint256 token_id) public {
        cur_token_id = token_id;
        address token_addr = tokens_list[token_id];

        optional(uint256) pubkey;
        IRootToken(token_addr).getDetails{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setTokenDetails),
            onErrorId: 0
        }();
    }


    function queryTokenWalletAddress() public view {
        optional(uint256) pubkey;
        IRootToken(tokens_list[selected_token_id]).getWalletAddress{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setTokenWalletAddress),
            onErrorId: 0
        }(public_key, wallet_address);
    }

    function queryTokenWalletBalance() public view {
        optional(uint256) pubkey;
        ITokenWallet(token_wallet_address).balance{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setTokenWalletBalance),
            onErrorId: 0
        }();
    }


    // ---------------------------- CALLBACKS ---------------------------------
    function setTokens(address[] _tokens) public {
        tokens_list = _tokens;

        
        queryTokenDetails(0);
    }

    function setTokenDetails(rootTokenContractDetails _token_details) public {
        tokens_details.push(_token_details);

        if (cur_token_id == tokens_list.length - 1) {
            // show menu
            showTokensMenu();
        } else {
            queryTokenDetails(cur_token_id + 1);
        }
    }

    function setTokenWalletAddress(address _token_wallet_address) public {
        token_wallet_address = _token_wallet_address;
        string str = format("Your token wallet address - {}", token_wallet_address);
        Terminal.print(0, str);

        queryTokenWalletBalance();
    }

    function setTokenWalletBalance(uint128 _balance) public {
        token_wallet_balance = _balance;
        uint left_part = token_wallet_balance / 10 ** tokens_details[selected_token_id].decimals;
        uint right_part = token_wallet_balance % 10 ** tokens_details[selected_token_id].decimals;
        string str = format("Your balance - {}.{} {}", left_part, right_part, token_symbol);
        Terminal.print(0, str);

        getAmountToSend();
    }

    function success(uint64 res) public {
        Terminal.print(0, "Your tokens are successfully transfered!");
    }

    // ------------------------------ ERR HANDLERS --------------------------------

}
