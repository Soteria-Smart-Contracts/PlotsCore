console.log('merklegen.js loaded');


let whitelistAddresses = [
    {"address":"0x72703b554a7089f93ff1fc6cc6c0e623900a7b80","points":381791},
    {"address":"0x0955476b9daec02653e688b865660ca5417faad4","points":251068},
    {"address":"0x0f986ae926590dddacde9a1806daa4e015c07b01","points":195943},
    {"address":"0x2146c5e2777034c50a8ede7e4e5b67d132175168","points":144808},
  ];



const leafNodes = whitelistAddresses.map(data => keccak256(data));
const merkleTree = new MerkleTree(leafNodes, keccak256, { sortPairs: true});

// Get root hash of the `merkleeTree` in hexadecimal format (0x)
// Print out the Entire Merkle Tree.
const rootHash = merkleTree.getRoot();
const rootHashBytes32 = '0x' + merkleTree.getRoot().toString('hex');
console.log("Root Hash: ", rootHashBytes32);

// ***** ***** ***** ***** ***** ***** ***** ***** // 

// CLIENT-SIDE: Use `msg.sender` address to query and API that returns the merkle proof
// required to derive the root hash of the Merkle Tree

// ✅ Positive verification of address
const claimingAddress = leafNodes[6];
// ❌ Change this address to get a `false` verification
// const claimingAddress = keccak256("0X5B38DA6A701C568545DCFCB03FCB875F56BEDDD6");

// `getHexProof` returns the neighbour leaf and all parent nodes hashes that will
// be required to derive the Merkle Trees root hash.
const hexProof = merkleTree.getHexProof(claimingAddress);

// ✅ - ❌: Verify is claiming address is in the merkle tree or not.
// This would be implemented in your Solidity Smart Contract
console.log(merkleTree.verify(hexProof, claimingAddress, rootHash));