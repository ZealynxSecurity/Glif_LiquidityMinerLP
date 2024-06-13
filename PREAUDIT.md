<div style="display: flex; justify-content: center;">
  <img width="300" alt="image" src="image/Glifio.png">
</div>

# Questions

## Communications

### Main Point of Contact
- **Name:** Jonathan Schwartz
- **Telegram:** @jpschwartz

### Communication Channels
- **Preferred Channel:** Telegram

### Issue Sharing
- **Drafts of Severe Issues:** Yes, can share immediately with Jonathan

### Sync Meetings
- **Preference:** No async is fine unless we need a call to discuss a specific issue in more detail - can do ad hoc

## Documentation

### Availability
- **Documentation:** The source code is well commented and I will walk the auditors through the code and architecture.

### Up-to-date Status
- **Current:** Yes
- **Version Match:** Yes

## Prior Security Work

### Previous Audits
- **Audit History:** We've had 2 security researchers help review the code and write fuzz tests + formal verification.

### Formal Verification
- **Plan:** Yes

### Security-oriented Tooling
- **Tools:** Yes - forge fuzz tests, Echidna + Medusa

## Project

### Code Walkthrough
- **Scheduled:** Yes, 45 min should do.

### Code Origin
- **Forked/Inspiration:** No

### Production Status
- **Deployment:** No - report to Jonathan Schwartz if critical vulnerabilities are found.

### Deployment Schedule
- **Timeline:** Yes, probably July/August

### Target Chains
- **Chains:** FEVM Filecoin

### Code Freeze
- **Status:** There may be additional view functions added, but no core logic should be changed.

### Sensitive Parts
- **Concern:** I'm not fearful of any parts of the code. I'm concerned that we're forgetting helpful functionality to provide better UX. Currently investigating issues with imprecision.

### Least Tested Parts
- **Areas:** Complex scenario analysis.

### Difficult Parts
- **Challenge:** Getting the math and precision precision.

### Frequent Changes
- **Areas:** The core math aspects, mostly in `updateAccounting` and the various view functions.

### Attack Vectors
- **Current View:** I don't see any hack vectors currently, only potential annoying UX blockers and bad upgradeability.

### Relevant Integrations
- **Integrations:** Filecoin FEVM has unique precompiles, so we use certain libraries to call FEVM precompiles, which are not standard on EVM. The FEVM address space also has some unique quirks, however these things have been audited and used in production for over a year. There are no external integrations besides the GLIF token, these external elements work as documented.

### Known ERCs
- **Implementation:** Not in this contract.

### Libraries Used
- **Libraries:** We're using Open Zeppelin libraries where applicable. We also use our own fork of the Open Zeppelin Ownable contract that handles Filecoin native addresses.

### Upgradeable Contracts
- **Status:** The contracts are not upgradeable.

## Roles

### Main Roles
- **Roles:** The owner of the contract can set various parameters like the 

### Assumptions
- **Benevolence:** Yes

### Permissioned Roles
- **Holders:** Multisig wallet

### Decentralization Plans
- **Progress:** We're currently working on an Open Zeppelin Governor contract with the Tally team to make progress towards these efforts.

## Report

### Preferred Format
- **Format:** Whatever is easiest for the auditor, we're not worried so much about a polished report.

### Status Reports
- **Frequency:** No we trust the auditors will get the job done.

### Public Report
- **Decision:** Depends on what we find.
