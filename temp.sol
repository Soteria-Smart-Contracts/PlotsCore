// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//create a deployer contract for both the token and the distributor

contract Deployer {
    PlotsFinance public token;
    MerkleDistributor public distributor;

    constructor(
        bytes32[] memory _merkleRoots,
        uint256[] memory _cliffPeriods,
        uint256[] memory _tgePercentages,
        uint256[] memory _totalRounds
    ) {
        token = new PlotsFinance("Plots Finance", "PLOTS", address(this));
        distributor = new MerkleDistributor(
            _merkleRoots,
            _cliffPeriods,
            _tgePercentages,
            _totalRounds
        );
    }
}

contract MerkleDistributor {
    IERC20 public token;
    address public owner;

    uint256 public timeUnit = 30 days; // Set to 30 days for production

    struct Distribution {
        bytes32 merkleRoot;    // Merkle root for this distribution
        uint256 cliffPeriod;   // Cliff period before vesting starts
        uint256 tgePercentage; // Initial percentage claimable at TGE
        uint256 totalRounds;   // Total number of vesting rounds
    }

    Distribution[] public distributions;

    mapping(address => mapping(uint256 => uint256)) public claimedAmount; // Tracks claimed amounts
    mapping(address => mapping(uint256 => bool)) public hasClaimed; // Tracks if a user has claimed all tokens in a distribution

    event Claimed(address indexed account, uint256 amount, uint256 distributionIndex);


    constructor(
        bytes32[] memory _merkleRoots,
        uint256[] memory _cliffPeriods,
        uint256[] memory _tgePercentages,
        uint256[] memory _totalRounds
    ) {
        require(
            _merkleRoots.length == _cliffPeriods.length &&
            _merkleRoots.length == _tgePercentages.length &&
            _merkleRoots.length == _totalRounds.length,
            "Input arrays length mismatch"
        );

        owner = msg.sender;

        for (uint256 i = 0; i < _merkleRoots.length; i++) {
            distributions.push(Distribution({
                merkleRoot: _merkleRoots[i],
                cliffPeriod: block.timestamp + (_cliffPeriods[i] * timeUnit),
                tgePercentage: _tgePercentages[i],
                totalRounds: _totalRounds[i]
            }));
        }
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /** @notice Allows users to claim their tokens or others to claim on their behalf */
    function claim(
        address claimant,
        uint256 amount,
        bytes32[] calldata merkleProof,
        uint256 distributionIndex
    ) public {
        require(distributionIndex < distributions.length, "Invalid distribution index");
        Distribution storage dist = distributions[distributionIndex];

        // Verify the merkle proof
        bytes32 node = keccak256(abi.encodePacked(claimant, amount));
        require(MerkleProof.verify(merkleProof, dist.merkleRoot, node), "Invalid proof");

        // Ensure the cliff period has passed
        require(block.timestamp >= dist.cliffPeriod, "Cliff period not over");

        // Calculate current round
        uint256 elapsedTime = block.timestamp - dist.cliffPeriod;
        uint256 currentRound = (elapsedTime / timeUnit) + 1;
        if (currentRound > dist.totalRounds) {
            currentRound = dist.totalRounds;
        }

        // Calculate total claimable amount up to current round
        uint256 totalClaimableAmount;
        uint256 tgeAmount = (amount * dist.tgePercentage) / 100;
        uint256 vestingAmount = amount - tgeAmount;

        if (currentRound == 1) {
            totalClaimableAmount = tgeAmount;
        } else {
            uint256 roundsElapsed = currentRound - 1;
            uint256 perRoundVestingAmount = vestingAmount / (dist.totalRounds - 1);
            totalClaimableAmount = tgeAmount + (perRoundVestingAmount * roundsElapsed);
        }

        // Calculate amount to claim
        uint256 amountToClaim = totalClaimableAmount - claimedAmount[claimant][distributionIndex];
        require(amountToClaim > 0, "No tokens to claim");

        // Update claimed amount
        claimedAmount[claimant][distributionIndex] += amountToClaim;

        // Mark as fully claimed if all rounds are completed
        if (currentRound == dist.totalRounds) {
            hasClaimed[claimant][distributionIndex] = true;
        }

        // Mint tokens to the claimant
        require(token.mint(claimant, amountToClaim), "Mint failed");

        emit Claimed(claimant, amountToClaim, distributionIndex);
    }

    /** @notice Allows batch claiming for efficiency */
    function multiClaim(
        address[] calldata claimants,
        uint256[] calldata amounts,
        bytes32[][] calldata merkleProofs,
        uint256[] calldata distributionIndexes
    ) external {
        require(
            amounts.length == distributionIndexes.length &&
            amounts.length == merkleProofs.length &&
            claimants.length == amounts.length,
            "Mismatched inputs"
        );

        for (uint256 i = 0; i < amounts.length; i++) {
            claim(claimants[i], amounts[i], merkleProofs[i], distributionIndexes[i]);
        }
    }

    function setToken(address _token) public onlyOwner {
        require(address(token) == address(0), "Token already set");
        token = IERC20(_token);

        owner = address(0);
    }
}


contract PlotsFinance {
    uint256 public totalSupply;
    uint256 public maxSupply = 1000000000000000000000000000;
    string public name;
    string public symbol;
    uint8 public decimals;
    address private ZeroAddress;
    address public distributor;
    //variable Declarations
      
    event Transfer(address indexed from, address indexed to, uint256 value);    
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BurnEvent(address indexed burner, uint256 indexed buramount);
    
    mapping(address => uint256) balances;

    mapping(address => mapping (address => uint256)) public allowance;
    
    
    constructor(string memory _name, string memory _symbol, address _distributor){
        totalSupply = 0;
        name = _name;
        symbol = _symbol;
        decimals = 18;
        distributor = _distributor;
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


    function transfer(address _to, uint256 _amount) public returns (bool) {
        require(_amount <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender]-(_amount);
        balances[_to] = balances[_to]+(_amount);
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }


    function Mint(address _MintTo, uint256 _MintAmount) public {
        require(msg.sender == distributor);
        require(totalSupply+(_MintAmount) <= maxSupply);
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



}


interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library MerkleProof {
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current proof element)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current proof element + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Verify the computed hash matches the root
        return computedHash == root;
    }
}
