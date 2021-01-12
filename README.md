# AWS CodeDeploy Action
To automatically deploy applications to EC2 via CodeDeploy.

---

## Usage

---
### Install as Local Action
For quicker troubleshooting cycles, the action can be copied directly into another project. This way, changes to the action and it's usage can happen simultaneously, in one commit.

1. Copy this repository into your other project as `.github/actions/aws-codedeploy-action`. Be careful: simply cloning in place will likely install it as a submodule--make sure to copy the files without `.git`
2. In your other project's workflow, in the action step, set\
   `uses: ./.github/actions/aws-codedeploy-action`
