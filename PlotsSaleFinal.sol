// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract Plots_MultiToken_Presale {
    // Token Addresses
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    // Chainlink Price Feeds
    address public constant USDTPriceFeed = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46;

    // Admin Address
    address public Admin;

    // Merkle Root
    bytes32 public MerkleRoot = 0xc7643eceeaffb11e5d3cf61658207d4b9e96ff74e301a0c21204d41ea0452baf;

    // Params
    uint256 public SaleStart;
    uint256 public SaleEnd;
    uint256 public PhaseOnePrice;
    uint256 public PhaseTwoPrice;

    uint256 public TotalRaised;
    uint256 public SaleCap;
    SalePhase public Phase;
    address[] public Participants;
    PurchaseHistory[] public SaleHistory;

    mapping(address => uint256) public Allocation;
    mapping(address => bool) public AllocationSet;
    mapping(address => UserType) public RegisteredAs;
    mapping(address => uint256) public PlotsToReceive;

    enum SalePhase { AwaitingStart, Registered, Public, Over } 

    enum UserType { TwentyFiveFDV, FifteenFDV }

    struct PurchaseHistory{
        address user;
        UserType RegisterationTier;
        uint256 timestamp;
        uint256 USDequivalent;
    }

    modifier OnlyAdmin() {
        require(msg.sender == Admin, "Only Admin");
        _;
    }

    modifier ActiveSaleOnly() {
        require(GetSaleStatus() == SalePhase(1) || GetSaleStatus() == SalePhase(2) , "Sale is not active");
        _;
    }

    event TokensPurchased(address indexed buyer, uint256 amount, address token);
    event ProceedsSentToTreasury(uint256 usdtAmount, uint256 usdcAmount, uint256 ethAmount);
    event SaleParamsSet(uint256 saleStart, uint256 saleEnd, uint256 phaseOnePrice, uint256 phaseTwoPrice, uint256 phaseOneCap);

    constructor()  {
        SaleStart = block.timestamp + 600;
        SaleEnd = block.timestamp + 216000;
        PhaseOnePrice = 15000000000000000;
        PhaseTwoPrice = 25000000000000000;
        Phase = SalePhase(0);
        
        SaleCap = 1500000000000;
        Admin = 0xc932b3a342658A2d3dF79E4661f29DfF6D7e93Ce;

        emit SaleParamsSet(SaleStart, SaleEnd, PhaseOnePrice, PhaseOnePrice, PhaseTwoPrice);
    }


    // Purchase Functions
    function PurchaseWithETH(UserType UserRegistration, uint256 UserPoints, bytes32[] memory Proof) public ActiveSaleOnly payable {
        if (UserRegistration == UserType.TwentyFiveFDV && GetSaleStatus() == SalePhase(1)) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(msg.sender))), "Invalid credentials");
        } else if (UserRegistration == UserType.FifteenFDV) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(StringUtils.concatenate(msg.sender, UserPoints)))), "Invalid credentials");
        }

        if (PlotsToReceive[msg.sender] == 0){
            Participants.push(msg.sender);
        }

        if (!AllocationSet[msg.sender] && UserRegistration == UserType.FifteenFDV) {
            SetAllocationInUSD(UserPoints);
            AllocationSet[msg.sender] = true;
            RegisteredAs[msg.sender] = UserType(1);
        }else if(!AllocationSet[msg.sender]){
            RegisteredAs[msg.sender] = UserType(0);
            SetAllocationInUSD(50000); //Becomes 25k usd
        }else{
            require(RegisteredAs[msg.sender] == UserRegistration);
        }

        uint256 plotsToReceive = ConvertEthToPlots(msg.value, UserRegistration);
        uint256 StableEquivalent = ConvertEthToStable(msg.value);
        require(StableEquivalent >= 50000000, "Invalid amount");
        require(TotalRaised + StableEquivalent <= SaleCap, "Sale cap reached");

        require(Allocation[msg.sender] >= StableEquivalent, "Invalid allocation");
        Allocation[msg.sender] -= StableEquivalent;

        TotalRaised += StableEquivalent;
        PlotsToReceive[msg.sender] += plotsToReceive;

        SaleHistory.push(PurchaseHistory(msg.sender, UserRegistration, block.timestamp, StableEquivalent));
        emit TokensPurchased(msg.sender, plotsToReceive, address(0));
    }

    function PurchaseWithUSDT(uint256 amount, UserType UserRegistration, uint256 UserPoints, bytes32[] memory Proof) public ActiveSaleOnly {
        require(amount >= 50000000, "Invalid amount");
        require(TotalRaised + amount <= SaleCap, "Sale cap reached");
        if (UserRegistration == UserType.TwentyFiveFDV && GetSaleStatus() == SalePhase(1)) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(msg.sender))), "Invalid credentials");
        } else if (UserRegistration == UserType.FifteenFDV) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(StringUtils.concatenate(msg.sender, UserPoints)))), "Invalid credentials");
            require(PlotsToReceive[msg.sender] == 0); //This requirement is to avoid 15fdv users from setting their allocation to 50k during the public sale then reentering with credentials to buy more tokens at the lower price
        }

        if (PlotsToReceive[msg.sender] == 0){
            Participants.push(msg.sender);
        }

        if (!AllocationSet[msg.sender] && UserRegistration == UserType.FifteenFDV) {
            SetAllocationInUSD(UserPoints);
            AllocationSet[msg.sender] = true;
            RegisteredAs[msg.sender] = UserType(1);
        }else if(!AllocationSet[msg.sender]){
            RegisteredAs[msg.sender] = UserType(0);
            SetAllocationInUSD(50000); //Becomes 25k usd
        }else{
            require(RegisteredAs[msg.sender] == UserRegistration);
        }

        uint256 plotsToReceive = ConvertStableToPlots(amount, UserRegistration);
        require(Allocation[msg.sender] >= amount, "Invalid allocation");
        Allocation[msg.sender] -= amount;
        
        ISafeERC20(USDT).safeTransferFrom(msg.sender, address(this), amount); //CONVERTED TO ERC20 REGULAR SEND FOR TEST, CONVERT TO SAFE_ERC20 SEND FOR LIVE DEPLOY
        TotalRaised += amount;
        PlotsToReceive[msg.sender] += plotsToReceive;

        SaleHistory.push(PurchaseHistory(msg.sender, UserRegistration, block.timestamp, amount));
        emit TokensPurchased(msg.sender, plotsToReceive, USDT);
    }

    function PurchaseWithUSDC(uint256 amount, UserType UserRegistration, uint256 UserPoints, bytes32[] memory Proof) public ActiveSaleOnly {
        require(amount >= 50000000, "Invalid amount");
        require(TotalRaised + amount <= SaleCap, "Sale cap reached");
        if (UserRegistration == UserType.TwentyFiveFDV && GetSaleStatus() == SalePhase(1)) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(msg.sender))), "Invalid credentials");
        } else if (UserRegistration == UserType.FifteenFDV) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(StringUtils.concatenate(msg.sender, UserPoints)))), "Invalid credentials");
        }

        if (PlotsToReceive[msg.sender] == 0){
            Participants.push(msg.sender);
        }

        if (!AllocationSet[msg.sender] && UserRegistration == UserType.FifteenFDV) {
            SetAllocationInUSD(UserPoints);
            AllocationSet[msg.sender] = true;
            RegisteredAs[msg.sender] = UserType(1);
        }else if(!AllocationSet[msg.sender]){
            RegisteredAs[msg.sender] = UserType(0);
            SetAllocationInUSD(50000); //Becomes 25k usd
        }else{
            require(RegisteredAs[msg.sender] == UserRegistration);
        }

        uint256 plotsToReceive = ConvertStableToPlots(amount, UserRegistration);
        require(Allocation[msg.sender] >= amount, "Invalid allocation");
        Allocation[msg.sender] -= amount;
        
        ISafeERC20(USDC).safeTransferFrom(msg.sender, address(this), amount); //CONVERTED TO REGULAR SEND FOR TEST, CONVERT TO safetransferfrom SEND FOR LIVE DEPLOY
        TotalRaised += amount;
        PlotsToReceive[msg.sender] += plotsToReceive;

        SaleHistory.push(PurchaseHistory(msg.sender, UserRegistration, block.timestamp, amount));
        emit TokensPurchased(msg.sender, plotsToReceive, USDC);
    }

    function SetAllocationInUSD(uint256 allocation) internal {
        Allocation[msg.sender] = allocation * 10**6 / 2;
    }

    // Utility Functions

    function ConvertEthToStable(uint256 amountIn) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(USDTPriceFeed);
        (, int256 priceusdt, , , ) = priceFeed.latestRoundData();
        uint256 uintprice = uint256(priceusdt);
        uint256 amountInWei = amountIn * 10**6;
        uint256 usdAmount = (amountInWei) / uintprice;
        return usdAmount;
    }

    function ConvertStableToPlots(uint256 amountIn, UserType rate) public view returns (uint256) {
        //if the rate is 25FDV, then the price is phase two price, else it is phase two price 
        if (rate == UserType.TwentyFiveFDV) {
            return (amountIn * 10**30) / PhaseTwoPrice;
        } else {
            return (amountIn * 10**30) / PhaseOnePrice;
        }
    }

    function ConvertEthToPlots(uint256 amountIn, UserType rate) public view returns (uint256) {
        uint256 StableEquivalent = ConvertEthToStable(amountIn);
        return ConvertStableToPlots(StableEquivalent, rate);
    }    

    function VerifySaleEligibility(UserType UserRegistration, uint256 UserPoints, address UserAddress, bytes32[] memory proof) public view returns (bool) {
        if (UserRegistration == UserType.TwentyFiveFDV) {
            return VerifyCredentials(proof, keccak256(abi.encodePacked(UserAddress)));
        } else if (UserRegistration == UserType.FifteenFDV) {
            return VerifyCredentials(proof, keccak256(abi.encodePacked(StringUtils.concatenate(UserAddress, UserPoints))));
        }
        return false;
    }

    function VerifyCredentials(bytes32[] memory proof, bytes32 leaf) public view returns (bool) {
        return verify(proof, MerkleRoot, leaf);
    }

    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == root;
    }

    function ChangeSaleEnd(uint256 _SaleEnd) public OnlyAdmin {
        SaleEnd = _SaleEnd;
    }

    function SendProceedsToTreasury() public OnlyAdmin {
        uint256 usdtBalance = ERC20(USDT).balanceOf(address(this));
        uint256 usdcBalance = ERC20(USDC).balanceOf(address(this));
        uint256 ethBalance = address(this).balance;

        ISafeERC20(USDT).safeTransfer(Admin, usdtBalance);
        ISafeERC20(USDC).safeTransfer(Admin, usdcBalance);
        payable(Admin).transfer(ethBalance);

        emit ProceedsSentToTreasury(usdtBalance, usdcBalance, ethBalance);
    }

    function GetSaleStatus() public view returns (SalePhase Status) {
        if (block.timestamp >= SaleStart && block.timestamp <= SaleEnd && TotalRaised < SaleCap) {
            if(SaleStart + 43200 >= block.timestamp){
                return SalePhase(1);
            }
            else{
                return SalePhase(2);
            }
        } else if(SaleEnd <= block.timestamp){
            return SalePhase(3);
        } else if(SaleStart >= block.timestamp){
            return SalePhase(0);
        }
    }

    function LatestSaleIndex() public view returns(uint256 index){
        return(SaleHistory.length - 1);
    }
}

contract ERC20 {
    uint256 public tokenCap;
    uint256 public totalSupply;
    string public name;
    string public symbol;
    uint8 public decimals;
    address private operator;
    address private ZeroAddress;
    //variable Declarations
    
      
    event Transfer(address indexed from, address indexed to, uint256 value);    
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BurnEvent(address indexed burner, uint256 indexed buramount);
    event ManageMinterEvent(address indexed newminter);
    //Event Declarations 
    
    mapping(address => uint256) balances;

    mapping(address => mapping (address => uint256)) public allowance;
    
    mapping(address => bool) minter;
    
    constructor(uint256 _TokenCap, string memory _name, string memory _symbol){
        tokenCap = _TokenCap;
        totalSupply = 0;
        name = _name;
        symbol = _symbol;
        decimals = 18;
        operator = msg.sender;
    }
    
    
    function balanceOf(address Address) public view returns (uint256 balance){
        return balances[Address];

    }

    function approve(address delegate, uint _amount) public returns (bool) {
        allowance[msg.sender][delegate] = _amount;
        emit Approval(msg.sender, delegate, _amount);
        return true;
    }
    //Approves an address to spend your coins

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        require(_amount <= balances[_from]);    
        require(_amount <= allowance[_from][msg.sender]); 
    
        balances[_from] = balances[_from]-(_amount);
        allowance[_from][msg.sender] = allowance[_from][msg.sender]-(_amount);
        balances[_to] = balances[_to]+(_amount);
        emit Transfer(_from, _to, _amount);
        return true;
    }
    //Transfer From an other address


    function transfer(address _to, uint256 _amount) public returns (bool) {
        require(_amount <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender]-(_amount);
        balances[_to] = balances[_to]+(_amount);
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }


    function Mint(address _MintTo, uint256 _MintAmount) public {
        require (minter[msg.sender] == true);
        require (totalSupply+(_MintAmount) <= tokenCap);
        balances[_MintTo] = balances[_MintTo]+(_MintAmount);
        totalSupply = totalSupply+(_MintAmount);
        ZeroAddress = 0x0000000000000000000000000000000000000000;
        emit Transfer(ZeroAddress ,_MintTo, _MintAmount);
    }
    //Mints tokens to your address 


    function Burn(uint256 _BurnAmount) public {
        require (balances[msg.sender] >= _BurnAmount);
        balances[msg.sender] = balances[msg.sender]-(_BurnAmount);
        totalSupply = totalSupply-(_BurnAmount);
        ZeroAddress = 0x0000000000000000000000000000000000000000;
        emit Transfer(msg.sender, ZeroAddress, _BurnAmount);
        emit BurnEvent(msg.sender, _BurnAmount);
        
    }

    function ManageMinter(bool IsMinter, address _address) public returns(address){
        require (msg.sender == operator);

        minter[_address] = IsMinter;

        emit ManageMinterEvent(_address);
        return (_address);
    }


}

interface ISafeERC20 {
    function safeTransfer(address to, uint256 value) external;
    function safeTransferFrom(address from, address to, uint256 value) external;
    function transferFrom(address _from, address _to, uint256 _amount) external;
    function transfer(address _to, uint256 _amount) external;
}

interface AggregatorV3Interface {
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

library StringUtils {
    // Convert address to string
    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint(uint8(value[i + 12] >> 4))];
            str[3 + i * 2] = alphabet[uint(uint8(value[i + 12] & 0x0f))];
        }
        return string(str);
    }

    // Convert uint256 to string
    function uintToString(uint256 _value) internal pure returns (string memory) {
        if (_value == 0) {
            return "0";
        }
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }

    // Function to concatenate address and points
    function concatenate(address _addr, uint256 _points) internal pure returns (string memory) {
        string memory addrStr = addressToString(_addr);
        string memory pointsStr = uintToString(_points);
        return string(abi.encodePacked(addrStr, pointsStr));
    }
}


//Merkle Verification Libraries
library Hashes {
    /**
     * @dev Commutative Keccak256 hash of a sorted pair of bytes32. Frequently used when working with merkle proofs.
     *
     * NOTE: Equivalent to the `standardNodeHash` in our https://github.com/OpenZeppelin/merkle-tree[JavaScript library].
     */
    function commutativeKeccak256(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? _efficientKeccak256(a, b) : _efficientKeccak256(b, a);
    }

    /**
     * @dev Implementation of keccak256(abi.encode(a, b)) that doesn't allocate or expand memory.
     */
    function _efficientKeccak256(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}

library MerkleProof {
    /**
     *@dev The multiproof provided is not valid.
     */
    error MerkleProofInvalidMultiproof();

    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        return processProof(proof, leaf) == root;
    }

    /**
     * @dev Calldata version of {verify}
     */
    function verifyCalldata(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        return processProofCalldata(proof, leaf) == root;
    }

    /**
     * @dev Returns the rebuilt hash obtained by traversing a Merkle tree up
     * from `leaf` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the root of the tree. When processing the proof, the pairs
     * of leafs & pre-images are assumed to be sorted.
     */
    function processProof(bytes32[] memory proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = Hashes.commutativeKeccak256(computedHash, proof[i]);
        }
        return computedHash;
    }

    /**
     * @dev Calldata version of {processProof}
     */
    function processProofCalldata(bytes32[] calldata proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = Hashes.commutativeKeccak256(computedHash, proof[i]);
        }
        return computedHash;
    }

    /**
     * @dev Returns true if the `leaves` can be simultaneously proven to be a part of a Merkle tree defined by
     * `root`, according to `proof` and `proofFlags` as described in {processMultiProof}.
     *
     * CAUTION: Not all Merkle trees admit multiproofs. See {processMultiProof} for details.
     */
    function multiProofVerify(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return processMultiProof(proof, proofFlags, leaves) == root;
    }

    /**
     * @dev Calldata version of {multiProofVerify}
     *
     * CAUTION: Not all Merkle trees admit multiproofs. See {processMultiProof} for details.
     */
    function multiProofVerifyCalldata(
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return processMultiProofCalldata(proof, proofFlags, leaves) == root;
    }

    /**
     * @dev Returns the root of a tree reconstructed from `leaves` and sibling nodes in `proof`. The reconstruction
     * proceeds by incrementally reconstructing all inner nodes by combining a leaf/inner node with either another
     * leaf/inner node or a proof sibling node, depending on whether each `proofFlags` item is true or false
     * respectively.
     *
     * CAUTION: Not all Merkle trees admit multiproofs. To use multiproofs, it is sufficient to ensure that: 1) the tree
     * is complete (but not necessarily perfect), 2) the leaves to be proven are in the opposite order they are in the
     * tree (i.e., as seen from right to left starting at the deepest layer and continuing at the next layer).
     */
    function processMultiProof(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32 merkleRoot) {
        // This function rebuilds the root hash by traversing the tree up from the leaves. The root is rebuilt by
        // consuming and producing values on a queue. The queue starts with the `leaves` array, then goes onto the
        // `hashes` array. At the end of the process, the last hash in the `hashes` array should contain the root of
        // the Merkle tree.
        uint256 leavesLen = leaves.length;
        uint256 proofLen = proof.length;
        uint256 totalHashes = proofFlags.length;

        // Check proof validity.
        if (leavesLen + proofLen != totalHashes + 1) {
            revert MerkleProofInvalidMultiproof();
        }

        // The xxxPos values are "pointers" to the next value to consume in each array. All accesses are done using
        // `xxx[xxxPos++]`, which return the current value and increment the pointer, thus mimicking a queue's "pop".
        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        uint256 proofPos = 0;
        // At each step, we compute the next hash using two values:
        // - a value from the "main queue". If not all leaves have been consumed, we get the next leaf, otherwise we
        //   get the next hash.
        // - depending on the flag, either another value from the "main queue" (merging branches) or an element from the
        //   `proof` array.
        for (uint256 i = 0; i < totalHashes; i++) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = proofFlags[i]
                ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                : proof[proofPos++];
            hashes[i] = Hashes.commutativeKeccak256(a, b);
        }

        if (totalHashes > 0) {
            if (proofPos != proofLen) {
                revert MerkleProofInvalidMultiproof();
            }
            unchecked {
                return hashes[totalHashes - 1];
            }
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }

    /**
     * @dev Calldata version of {processMultiProof}.
     *
     * CAUTION: Not all Merkle trees admit multiproofs. See {processMultiProof} for details.
     */
    function processMultiProofCalldata(
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32 merkleRoot) {
        // This function rebuilds the root hash by traversing the tree up from the leaves. The root is rebuilt by
        // consuming and producing values on a queue. The queue starts with the `leaves` array, then goes onto the
        // `hashes` array. At the end of the process, the last hash in the `hashes` array should contain the root of
        // the Merkle tree.
        uint256 leavesLen = leaves.length;
        uint256 proofLen = proof.length;
        uint256 totalHashes = proofFlags.length;

        // Check proof validity.
        if (leavesLen + proofLen != totalHashes + 1) {
            revert MerkleProofInvalidMultiproof();
        }

        // The xxxPos values are "pointers" to the next value to consume in each array. All accesses are done using
        // `xxx[xxxPos++]`, which return the current value and increment the pointer, thus mimicking a queue's "pop".
        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        uint256 proofPos = 0;
        // At each step, we compute the next hash using two values:
        // - a value from the "main queue". If not all leaves have been consumed, we get the next leaf, otherwise we
        //   get the next hash.
        // - depending on the flag, either another value from the "main queue" (merging branches) or an element from the
        //   `proof` array.
        for (uint256 i = 0; i < totalHashes; i++) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = proofFlags[i]
                ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                : proof[proofPos++];
            hashes[i] = Hashes.commutativeKeccak256(a, b);
        }

        if (totalHashes > 0) {
            if (proofPos != proofLen) {
                revert MerkleProofInvalidMultiproof();
            }
            unchecked {
                return hashes[totalHashes - 1];
            }
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }
}
