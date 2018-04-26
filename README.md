# aws-rollback
AWS CLI script that rolls back the EC2 instances to previous snapshot.

## Idea

The idea behind the script is to use it to rollback multiple AWS EC2 instances to specified snapshot. If you have some AWS environment that you need to rollback to previous state, this can help you achieve the task. You need to specify the list of instances and their snapshots to which they will be rolled back.

## Pre requirements

1. Install `aws-cli` on your server that will be the controller of instances.
    - Ubuntu/Debian: `apt-get install awscli`
    - CentOs/RedHat: https://docs.aws.amazon.com/streams/latest/dev/kinesis-tutorial-cli-installation.html
2. Create an API access key by following this: https://docs.aws.amazon.com/general/latest/gr/managing-aws-access-keys.html
3. In order to use the script you first need to have setup AWS credentials for user that will use `aws-cli`. Follow the link https://docs.aws.amazon.com/cli/latest/reference/configure/ to configure the aws tool.

## Usage

`./aws-rollback.sh <server_list_file> <region_id> <availability_zone> [timeout]`

- **server_list_file**
    Should containt list of EC2 instances with their devices and snapshots.
    Example:
    ```
    i-0979e19f5b5328bfa /dev/sda1 snap-0646898a51e7cbfcb
    i-010a8afdd343bac5f /dev/xvda snap-092bd0ea303a530b9
    i-010a8afdd343bac5f /dev/sdb  snap-025e2c69ca0aa40d6
    ```
    If the instance has two volumes attached just list it twice like in the example above, but specify the correct snapshot for the volume you want to rollback.
- **region_id**
    The region in which EC2 instances are. More info on the link below.

    https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html#concepts-available-regions
- **availability_zone**
    The zone in which volumes and instances are located. More info on the link below.

    https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html
- **timeout**
    Optional parameter which tells you how much should the waiting for status take in seconds. Default is 120.

### Example

`./aws-rollback.sh servers.txt sa-east-1 sa-east-1a`

This will run the rollback of all instances in the *servers.txt* file located in the *sa-east-1* zone.

## Running automatically?

The script can be scheduled via cronjob for example in some time in the evening, and will run until all instances are rolled back to the snapshots specified.
