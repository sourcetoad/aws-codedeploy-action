# AWS CodeDeploy Action

To automatically deploy applications to EC2 via CodeDeploy.

---

## Usage

The best example is just a snippet of the workflow with all options.

Laravel (All Properties) Example

```yaml
- name: AWS CodeDeploy
  uses: sourcetoad/aws-codedeploy-action@v1
  with:
    aws_access_key: ${{ secrets.AWS_ACCESS_KEY }}
    aws_secret_key: ${{ secrets.AWS_SECRET_KEY }}
    aws_region: us-east-1
    codedeploy_name: project
    codedeploy_group: prod
    codedeploy_register_only: true
    s3_bucket: project-codedeploy
    s3_folder: production
    excluded_files: '.git/* .env storage/framework/cache/* node_modules/*'
    max_polling_iterations: 60
    directory: ./
```

Laravel (Only Required) Example

* This leverages the official [GitHub Action for AWS Credentials](https://github.com/marketplace/actions/configure-aws-credentials-action-for-github-actions)

```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v1
  with:
    role-to-assume: arn:aws:iam::123456789100:role/my-github-actions-role
    aws-region: us-east-2

- name: AWS CodeDeploy
  uses: sourcetoad/aws-codedeploy-action@v1
  with:
    codedeploy_name: project
    codedeploy_group: prod
    s3_bucket: project-codedeploy
    s3_folder: production
```

* Remember to set specific permissions so we can communicate with the GitHub OIDC Endpoint.

```yaml
permissions:
    id-token: write
    contents: read
```

## Customizing

### inputs

Following inputs can be used as `step.with` keys

| Name                       | Required | Type    | Description                                                     |
|----------------------------|----------|---------|-----------------------------------------------------------------|
| `aws_access_key`           | No       | String  | IAM Access Key.                                                 |
| `aws_secret_key`           | No       | String  | IAM Secret Key.                                                 |
| `aws_region`               | No       | String  | AWS Region (default: `us-east-1`).                              |
| `codedeploy_name`          | Yes      | String  | CodeDeploy Project Name.                                        |
| `codedeploy_group`         | Yes      | String  | CodeDeploy Project Group.                                       |
| `codedeploy_config_name`   | No       | String  | If provided, override the default CodeDeploy Configuration name |
| `codedeploy_register_only` | No       | Boolean | If true, revision is registered not deployed.                   |
| `s3_bucket`                | Yes      | String  | S3 Bucket for archive to be uploaded.                           |
| `s3_folder`                | Yes      | String  | S3 Folder for archive to be uploaded within bucket.             |
| `excluded_files`           | No       | String  | Space delimited list of patterns to exclude from archive        |
| `directory`                | No       | String  | Directory to archive. Defaults to root of project.              |
| `custom_zip_flags`         | No       | String  | Flags to pass to `zip` command. (ie `zip "$FLAGS" ...`)         |
| `archive`                  | No       | String  | Zip to deploy. Defaults to empty (thus ignored)                 |
| `max_polling_iterations`   | No       | Number  | Number of 15s iterations to poll max. (default: `60`)           |
| `dry_run`                  | No       | Boolean | If true, no connection to AWS is made. Just local zip creation. |

## Skipping waiting during deployment
Some projects may not want to poll for a completion of a build. Setting `max_polling_iterations` to `0` will exit
the script after the deployment was kicked off. Progress will have to be monitored elsewhere.

## Archive or Build
Some projects may have a complex build system or even build the archive in a previous step. This is where
`directory` and `archive` come into play:

 * By default, `directory` will be used to zip that directory and deployed.
 * If `archive` is non-empty, it will be used in place of `directory`
 * `archive` must be zip filename including extension (ie `prod-backend-20220202.zip`).

## IAM Permissions
_If using manual Access/Secret keys_

You shouldn't be using a root user. Below are snippets of an inline policies with suggested permissions for the action. 

 * You might need to adapt these to fit your use case.
 * You will need to insert proper resources/ARNs to make the snippets below valid.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:Get*",
        "s3:List*",
        "s3:PutObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": [
        "arn:aws:s3:::project-codedeploy/*"
      ]
    }
  ]
}
```

 * This restricts the action to uploading an object and listing/getting the object so it can obtain the location for CodeDeploy
 * It is restricted to a specific bucket.

For deploying via CodeDeploy you will need another set of permissions.
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "codedeploy:CreateDeployment"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:codedeploy:codedeploy-arn"
            ]
        },
        {
            "Action": [
                "codedeploy:Batch*",
                "codedeploy:Get*",
                "codedeploy:List*",
                "codedeploy:RegisterApplicationRevision"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
```

 * These permissions are a rough example of allowing the user to list/get/register a revision for all resources
 * A specific permission statement exists to lock creating the deployment to a specific resource

---

### Install as Local Action

For quicker troubleshooting cycles, the action can be copied directly into another project. This way, changes to the
action, and its usage can happen simultaneously in one commit.

1. Copy this repository into your other project as `.github/actions/aws-codedeploy-action`. Be careful: simply cloning
   in place will likely install it as a submodule--make sure to copy the files without `.git`
    1. As a single command:
       ```shell
       mkdir .github/actions && \
       git clone --depth=1 --branch=master git@github.com:sourcetoad/aws-codedeploy-action.git .github/actions/aws-codedeploy-action && \
       rm -rf .github/actions/aws-codedeploy-action/.git
       ```
2. In your other project's workflow, in the action step, set
   `uses: ./.github/actions/aws-codedeploy-action`
