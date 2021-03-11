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
```yaml
- name: AWS CodeDeploy
  uses: sourcetoad/aws-codedeploy-action@v1
  with:
    aws_access_key: ${{ secrets.AWS_ACCESS_KEY }}
    aws_secret_key: ${{ secrets.AWS_SECRET_KEY }}
    codedeploy_name: project
    codedeploy_group: prod
    s3_bucket: project-codedeploy
    s3_folder: production
```

## Customizing
### inputs

Following inputs can be used as `step.with` keys

| Name             | Required | Type    | Description                        |
|------------------|----------|---------|------------------------------------|
| `aws_access_key` | Yes | String | IAM Access Key. |
| `aws_secret_key` | Yes | String | IAM Secret Key. |
| `aws_region` | No | String | AWS Region (default: `us-east-1`). |
| `codedeploy_name` | Yes | String | CodeDeploy Project Name. |
| `codedeploy_group` | Yes | String | CodeDeploy Project Group. |
| `codedeploy_register_only` | No | Boolean | If true, revision is registered not deployed. |
| `s3_bucket` | Yes | String | S3 Bucket for archive to be uploaded. |
| `s3_folder` | Yes | String | S3 Folder for archive to be uploaded within bucket. |
| `excluded_files` | No | String | Space delimited list of patterns to exclude from archive |
| `directory` | No | String | Directory to archive. Defaults to root of project. |
| `max_polling_iterations` | No | Number | Number of 15s iterations to poll max. (default: `60`) |

## IAM Permissions
You shouldn't be using a root user. Below is a snippet of an inline policy with perfect permissions for action.

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

---
### Install as Local Action
For quicker troubleshooting cycles, the action can be copied directly into another project. This way, changes to the action and it's usage can happen simultaneously, in one commit.

1. Copy this repository into your other project as `.github/actions/aws-codedeploy-action`. Be careful: simply cloning in place will likely install it as a submodule--make sure to copy the files without `.git`
2. In your other project's workflow, in the action step, set\
   `uses: ./.github/actions/aws-codedeploy-action`
