
variable "access_key" 		{}
variable "secret_key"		{}
variable "region"		{}
variable "vpc_cidr"		{}
variable "vpc_name" 		{}
variable "availability_zone" 	{}
variable "count"		{}
variable "allowed_cidr_ssh"	{}
variable "ami"			{}
variable "instance_type"	{}
variable "public_key_path"	{}
variable "private_key_path"	{}


#Required Version, Remote state conifguration with implicit lock
#===============================
terraform {
	required_version	= ">= 0.10.8"
	backend "azurerm" {
		storage_account_name 	= "remotestateterraform"
		container_name      	= "terraform-remote-state"
		key			= "aws.terraform.tfstate"
		access_key		= "GXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXg=="
	}
}

#Provider
#===============================
provider "aws" {
	access_key	= "${var.access_key}"
	secret_key	= "${var.secret_key}"
	region		= "${var.region}"
}
resource "aws_vpc" "vpc" {
	cidr_block		= "${var.vpc_cidr}"
	enable_dns_hostnames	= true	
	tags {
		Name		= "${var.vpc_name}"
	}
}
resource "aws_internet_gateway" "gw" {
	vpc_id = "${aws_vpc.vpc.id}"
	tags {
		Name = "IGW"
	}
}
resource "aws_route" "internet_access" {
	route_table_id         = "${aws_vpc.vpc.main_route_table_id}"
	destination_cidr_block = "0.0.0.0/0"
	gateway_id             = "${aws_internet_gateway.gw.id}"
}
resource "aws_subnet" "subnet" {
	count			= "${var.count}"
	vpc_id			= "${aws_vpc.vpc.id}"
	cidr_block		= "${cidrsubnet(var.vpc_cidr, 8, count.index + 1)}"
	availability_zone	= "${var.availability_zone}"
	map_public_ip_on_launch	= true
	tags {
		Name		= "${format("SUBNET-%d", count.index + 1)}"
	}
}

resource "aws_security_group" "sg" {
	name        		= "${format("Allow-from-%s", coalesce(var.allowed_cidr_ssh, "0.0.0.0/0"))}"
	description 		= "${format("Allow all inbound traffic from %s", coalesce(var.allowed_cidr_ssh, "0.0.0.0/0"))}"
	vpc_id      		= "${aws_vpc.vpc.id}"

}

resource "aws_security_group_rule" "sg-rule-allow-ssh" {
	type            	= "ingress"
	from_port		= 0
	to_port        		= 22
	protocol        	= "tcp"
	cidr_blocks     	= ["${coalesce(var.allowed_cidr_ssh, "0.0.0.0/0")}"]
	security_group_id 	= "${aws_security_group.sg.id}"
}

resource "aws_network_interface" "nic" {
	count			= "${var.count}"
	subnet_id       	= "${element(aws_subnet.subnet.*.id, count.index)}"
	security_groups 	= ["${aws_security_group.sg.id}"]
	tags {
		Name		= "${format("NIC-%d", count.index + 1)}"
	}
}

resource "aws_key_pair" "ubuntu_user" {
	key_name		= "ubuntu-user-key"
	public_key		= "${file(var.public_key_path)}"
}

resource "aws_instance" "ec2" {
	count				= "${var.count}"
	ami				= "${var.ami}"
	availability_zone		= "${var.availability_zone}"
	instance_type			= "${var.instance_type}"
	key_name			= "${aws_key_pair.ubuntu_user.id}"
	root_block_device {
		volume_type		= "standard"
		volume_size		= "8"
		delete_on_termination	= true
	}
	network_interface {
		device_index		= 0
		network_interface_id	= "${element(aws_network_interface.nic.*.id, count.index)}"
	}
	
	provisioner "file" {
		source			= "./assurity.splash"
		destination		= "~/assurity.splash"
		connection {
			type		= "ssh"
			user		= "ubuntu"
			private_key	= "${file(var.private_key_path)}"
		}
	}
	provisioner "file" {
		source			= "./00-header"
		destination		= "~/00-header"
		connection {
			type		= "ssh"
			user		= "ubuntu"
			private_key	= "${file(var.private_key_path)}"
		}
	}
	provisioner "remote-exec" {
		inline 	= [
			"sudo rm -rf /etc/update-motd.d/*",
			"sudo cp ~/assurity.splash /etc/update-motd.d/",
			"sudo cp ~/00-header /etc/update-motd.d/",
			"sudo chmod +x /etc/update-motd.d/00-header"
		]
		connection {
			type		= "ssh"
			user		= "ubuntu"
			private_key	= "${file(var.private_key_path)}"
		}
	}
	timeouts {
		create = "60m"
		delete = "2h"
	}

	tags {
		Name			= "${format("VM-%d", count.index + 1)}"
	}
	volume_tags {
		Name			= "${format("EBS-%d", count.index + 1)}"
	}
}

output "public-fqdn" {
	value				= "${aws_instance.ec2.*.public_dns}"
}

output "ssh-user" {
	value				= "ubuntu"
}

