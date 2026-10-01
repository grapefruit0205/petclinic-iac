import json
import logging
import os
import time

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)

REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
SECRET_ARN = os.environ["SECRET_ARN"]
SECRET_NAME = os.environ["SECRET_NAME"]
ASG_NAME = os.environ["ASG_NAME"]
SSM_DOCUMENT = os.environ["SSM_DOCUMENT"]
TAG_KEY = os.environ.get("INSTANCE_TAG_KEY", "aws:autoscaling:groupName")
TAG_VALUE = os.environ.get("INSTANCE_TAG_VALUE", "was-asg")
MIN_INSTANCES = int(os.environ.get("MIN_INSTANCES", "2"))

sm = boto3.client("secretsmanager", region_name=REGION)
asg = boto3.client("autoscaling", region_name=REGION)
ssm = boto3.client("ssm", region_name=REGION)


def current_version():
    meta = sm.describe_secret(SecretId=SECRET_ARN)
    for version, labels in meta.get("VersionIdsToStages", {}).items():
        if "AWSCURRENT" in labels:
            return version
    raise RuntimeError("AWSCURRENT version was not found")


def was_instances():
    result = asg.describe_auto_scaling_groups(AutoScalingGroupNames=[ASG_NAME])
    groups = result.get("AutoScalingGroups", [])
    if not groups:
        raise RuntimeError(f"Auto Scaling group {ASG_NAME} was not found")
    group = groups[0]
    instances = [
        item for item in group.get("Instances", [])
        if item.get("LifecycleState") == "InService"
    ]
    if len(instances) < MIN_INSTANCES:
        raise RuntimeError(f"Only {len(instances)} WAS instances are InService")
    bad = [item["InstanceId"] for item in instances if item.get("HealthStatus") != "Healthy"]
    if bad:
        raise RuntimeError("WAS fleet is not healthy before restart: " + ",".join(bad))
    return instances


def send_and_wait(instance_id, version, context):
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName=SSM_DOCUMENT,
        Parameters={"VersionId": [version]},
        Comment="Refresh Petclinic Tomcat after AWSCURRENT changed",
        TimeoutSeconds=300,
        MaxConcurrency="1",
        MaxErrors="0",
    )
    command_id = response["Command"]["CommandId"]
    deadline = time.monotonic() + min(300, max(1, (context.get_remaining_time_in_millis() - 3000) / 1000))
    while time.monotonic() < deadline:
        try:
            result = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") != "InvocationDoesNotExist":
                raise
            time.sleep(2)
            continue
        status = result.get("Status")
        if status == "Success":
            LOG.info("SSM restart and application checks succeeded for %s", instance_id)
            return
        if status in {"Cancelled", "TimedOut", "Failed", "Cancelling"}:
            raise RuntimeError(f"SSM command {command_id} failed on {instance_id}: {status}")
        time.sleep(3)
    raise TimeoutError(f"SSM command {command_id} did not finish on {instance_id}")


def wait_asg_healthy(instance_id, context):
    deadline = time.monotonic() + min(90, max(1, (context.get_remaining_time_in_millis() - 3000) / 1000))
    while time.monotonic() < deadline:
        groups = asg.describe_auto_scaling_groups(AutoScalingGroupNames=[ASG_NAME]).get("AutoScalingGroups", [])
        if not groups:
            raise RuntimeError(f"Auto Scaling group {ASG_NAME} disappeared")
        item = next((entry for entry in groups[0].get("Instances", []) if entry["InstanceId"] == instance_id), None)
        if item is None:
            raise RuntimeError(f"WAS instance {instance_id} left {ASG_NAME} during restart")
        if item.get("LifecycleState") == "InService" and item.get("HealthStatus") == "Healthy":
            return
        time.sleep(5)
    raise TimeoutError(f"WAS instance {instance_id} did not return to Healthy")


def handler(event, context):
    detail = event.get("detail", {}) if isinstance(event, dict) else {}
    if event.get("source") != "aws.secretsmanager" or event.get("detail-type") != "Secret Label Updated":
        LOG.info("Ignoring event with an unexpected source or type")
        return {"status": "ignored"}
    if detail.get("labelUpdated") != "AWSCURRENT" or detail.get("name") != SECRET_NAME:
        LOG.info("Ignoring event that does not update the configured AWSCURRENT secret")
        return {"status": "ignored"}

    version = current_version()
    instances = was_instances()
    LOG.info("Starting sequential refresh for %d WAS instances, version %s", len(instances), version)
    refreshed = []
    for item in instances:
        if context.get_remaining_time_in_millis() < 330_000:
            raise TimeoutError("Insufficient time remains to safely restart another WAS instance")
        instance_id = item["InstanceId"]
        send_and_wait(instance_id, version, context)
        wait_asg_healthy(instance_id, context)
        refreshed.append(instance_id)
    LOG.info("All WAS instances refreshed and healthy: %s", ",".join(refreshed))
    return {"status": "success", "version": version, "instances": refreshed}
