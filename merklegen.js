console.log('merklegen.js loaded');


let whitelistAddresses = [
  {
    "address": "0x04ab4c210f4d9814cd12a8804d249ec387f8ec61",
    "points": 1367789
  },
  {
    "address": "0x5186fc0017a983c51b3845f0ed7800a4c23ad0b0",
    "points": 414469
  },
  {
    "address": "0x72703b554a7089f93ff1fc6cc6c0e623900a7b80",
    "points": 381791
  },
  {
    "address": "0xb0cbf149ba9e7d0efb63235a08768a7b63f0652f",
    "points": 322092
  },
  {
    "address": "0xfc60750c91fd4090151ed42c5e88ff94e25e3f40",
    "points": 270608
  }
];

//convert the whitelistAddresses to an array of addresses with the points number appended to the address end
whitelistAddresses = whitelistAddresses.map((address) => {
  return address.address + address.points;
});

const leafNodes = whitelistAddresses.map(addr => keccak256(addr));
console.log("Leaf Nodes: ", leafNodes);
const merkleTree = new MerkleTree(leafNodes, keccak256, { sortPairs: true});

// Get root hash of the `merkleeTree` in hexadecimal format (0x)
// Print out the Entire Merkle Tree.
const rootHash = merkleTree.getRoot();
const rootHashBytes32 = '0x' + merkleTree.getRoot().toString('hex');
console.log("Root Hash: ", rootHashBytes32);

// ***** ***** ***** ***** ***** ***** ***** ***** // 

// CLIENT-SIDE
const claimingAddress = keccak256("0X5B38DA6A701C568545DCFCB03FCB875F56BEDDD6");

// `getHexProof` returns the neighbour leaf and all parent nodes hashes that will
// be required to derive the Merkle Trees root hash.
const hexProof = merkleTree.getHexProof(claimingAddress);

// ✅ - ❌: Verify is claiming address is in the merkle tree or not.
// This would be implemented in your Solidity Smart Contract
console.log(merkleTree.verify(hexProof, claimingAddress, rootHash));