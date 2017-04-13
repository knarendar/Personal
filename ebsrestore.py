#!/usr/bin/python
import boto3
import sys
import subprocess
import os
#boto3.utils
client = boto3.client('ec2')
import requests
response = requests.get('http://169.254.169.254/latest/meta-data/instance-id')
instance_id = response.text

## Functions Start here ###
def ebs_restore():
    #$instance_id
    import requests
    response = requests.get('http://169.254.169.254/latest/meta-data/instance-id')
    instance_id = response.text
    volInfo(instance_id)
    EBSVol = input("\n Please enter the EBS Volume# from the table above")
    print("\n Thank you")

def volInfo(arg1):
    host = arg1
    p1 = subprocess.Popen(["aws", "ec2", "describe-volumes", '--query', 'Volumes[*].{InstanceId:Attachments[0].InstanceId,EBSVolId:VolumeId,LinuxVolID:Attachments[0].Device,AZ:AvailabilityZone,VolumeType:VolumeType,IOPS:Iops,State:Stage,Size:Size,Vsad:Tags[?Key==`Vsad`].Value | [0],Owner:Tags[?Key==`Owner`].Value | [0]}', "--filters",  "Name=attachment.instance-id,Values=" + host, '--output', 'table'], stdout=subprocess.PIPE)
    output = p1.communicate()[0]

#volInfo("i-01490e98e9e726458")

ans=True
while ans:
    print("""
                Amazon Web Services
             EBS Volumes Restore Menu

    1.Restore EBS Volume on the Current Instance
    2.Restore EBS Volume on the diffenret Instance
    3.Restore EBS Volume by creating a new instance
    4.Exit/Quit
    """)
    ans=raw_input("What would you like to do? ")
    if ans=="1":
      ebs_restore()
      #ans=input("Please enter the EBS Vol ID ")
      print("\nEBS Volume attached to this instance")
    elif ans=="2":
      print("\n EBS Volume attached to different instance")
    elif ans=="3":
      print("\n EBS Volume by creating a new instance")
    elif ans=="4":
      print("\n Goodbye")
      ans = None
    else:
       print("\n Not Valid Choice Try again")
