# Centralization Risks in Hybrid Mode of `Commit-Reveal2` Protocol
## Description
The hybrid mode of Commit-Reveal2 protocol relies on the leader node (owner), a privileged role that is central but accountable coordinator that manages off-chain coordination, aggregates participant data, submits cryptographic commitments (e.g., Merkle roots) to the blockchain, and initiates on-chain dispute resolution when required. To ensure reliability, the leader node must post a security deposit (activation threshold) and may face slashing penalties if it fails to fulfill its responsibilities.

The audit team acknowledges that the current implementation of the hybrid Commit-Reveal2 protocol incorporates several mechanisms to reduce the centralization of the leader node’s authority, outlined as follows. Importantly, the leader node’s privileges do not put operators’ or users’ funds at risk, as these can be withdrawn or refunded as needed.

### CommitReveal2.sol
In the CommitReveal2 contract, the role owner (leader node) has authority over the following functions.

proposeEconomicParameters() to propose the updates of key economic parameters, activation thresdold and flat fee.
setPeriods() to set multiple periods used for timeouts.
proposeGasParameters() to propose the updates of key gas parameters to calculate the gas fee.
submitMerkleRoot() to submit a Merkle root for the current request.
resume() to restart the protocol once it's halted.
Any compromise of the owner account may allow an attacker to arbitrarily set critical state variables when the protocol is not in progress (e.g., via setPeriods()), or halt the protocol by refusing or failing to invoke resume().

As part of the protocol, malicious calls to submitMerkleRoot() with invalid Merkle roots would be punished, but such attempts remain a potential disruption vector if the owner account is compromised.

Although parameter updates proposed through proposeEconomicParameters() and proposeGasParameters() are protected by a 10-minute timelock, a compromised owner could still attempt to influence or misuse this process.

### src/CommitReveal2Storage.sol

    uint256 public constant SET_DELAY_TIME = 10 minutes;
CommitReveal2L2.sol
In the CommitReveal2L2 contract, the role owner (leader node) has authority over the following functions.

setL1FeeCoefficient() to set the s_l1FeeCoefficient (fee coefficient) between 0 to 100.
A compromised owner could also reset the s_l1FeeCoefficient when the protocol is not in progress, directly impacting gas fee calculations for the random number requests and gas compensation when calling the failure methods.

### DisputeLogics.sol
In the DisputeLogics contract, the role owner (leader node) has authority over the following functions.

requestToSubmitCv() to request any active operator to submit the cv on-chain.
requestToSubmitCo() to request any active operator to submit the co on-chain.
requestToSubmitS() to request any active operator to submit the secret on-chain.
If the owner account is compromised, an attacker could exploit its authority to request cv, co, and s from active operators. This may result in a griefing attack, as operators would be compelled to submit the requested data on-chain to avoid slashing. Furthermore, an operator could deliberately trigger the fallback mechanism to force other operators to submit data on-chain, which could similarly lead to a griefing attack. The team has acknowledged this behavior as part of the intended design.

### OperatorManager.sol
In the OperatorManager contract, the role owner has authority over the following functions.

transferOwnership() to transfer the ownership of the contract to another account.
completeOwnershipHandover() to transfer the ownership of the contract to the pending owner.
Finally, a compromised owner account could arbitrarily manipulate contract ownership at will.

## Recommendation
The risk describes the current project design and potentially makes iterations to improve in the security operation and level of decentralization, which in most cases cannot be resolved entirely at the present stage. We advise the client to carefully manage the privileged account's private key to avoid any potential risks of being hacked. In general, we strongly recommend centralized privileges or roles in the protocol be improved via a decentralized mechanism or smart-contract-based accounts with enhanced security practices, e.g., multi-signature wallets.

Indicatively, here are some feasible suggestions that would also mitigate the potential risk at a different level in terms of short-term and long-term:

### Short Term:
Timelock and Multisign (⅔, ⅗) combination mitigate by delaying the sensitive operation and avoiding a single point of key management failure.

Time-lock with reasonable latency, e.g., 48 hours, for awareness on privileged operations;
AND
Assignment of privileged roles to multi-signature wallets to prevent a single point of failure of the leader node due to the private key compromised;
AND
A medium/blog link for sharing the timelock contract and multi-signers addresses information with the public audience.

### Long Term:
Timelock and DAO, the combination, mitigate by applying decentralization and transparency.

Time-lock with reasonable latency, e.g., 48 hours, for awareness on privileged operations;
AND
Introduction of a DAO/governance/voting/consensus module to distribute the leader node's authority among multiple parties to increase transparency and user involvement.
AND
A medium/blog link for sharing the timelock contract, multi-signers addresses, and DAO information with the public audience.
Since certain operations are time-sensitive for the smooth functioning of the protocol and enforced with status checks, the use of a Timelock is not recommended. However, for key operations, it is strongly recommended to implement multi-signature controls.