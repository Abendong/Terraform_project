provider "aws" {
    region = "eu-west-1"
}
    
variable vpc_cidr_block {}
variable subnet_cidr_block {}
variable avail_zone {}
variable env_prefix {}
variable my_ip {}
variable instance_type {}
variable public_key_location {}
variable private_key_location {}

resource "aws_vpc" "myapp-vpc" {
    cidr_block = var.vpc_cidr_block
    tags = {
        Name: "${var.env_prefix}-vpc"
    }
}

resource "aws_subnet" "myapp-subnet-1" {
    vpc_id = aws_vpc.myapp-vpc.id
    cidr_block = var.subnet_cidr_block
    availability_zone = var.avail_zone
    tags = {
        Name: "${var.env_prefix}-subnet-1"
    }
}


resource "aws_internet_gateway" "myapp-igw" {
    vpc_id = aws_vpc.myapp-vpc.id
    tags = {
        Name: "${var.env_prefix}-igw"
    }
}

resource "aws_route_table" "myapp-route-table" {
    vpc_id = aws_vpc.myapp-vpc.id

    route{
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.myapp-igw.id
    }
    tags = {
        Name: "${var.env_prefix}-rtb"
    }
}

resource "aws_route_table_association" "a-rtb-subnet" {
    subnet_id = aws_subnet.myapp-subnet-1.id
    route_table_id = aws_route_table.myapp-route-table.id
}

resource "aws_default_security_group" "default-sg" {
    vpc_id = aws_vpc.myapp-vpc.id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks =[var.my_ip]
    }

    ingress {
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        cidr_blocks =["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks =["0.0.0.0/0"]
        prefix_list_ids = []
    }

    tags = {
        Name: "${var.env_prefix}-default-sg"
    }
}
data "aws_ami" "lattest-amazon-linux-image" {
    most_recent = true
    owners = ["amazon"]
    filter {
        name = "name"
        values = ["*ami-hvm-*-x86_64-gp2"]
    }
    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }
}

output "aws_ami_id" {
    value = data.aws_ami.lattest-amazon-linux-image.id
}

output "ec2_public_ip" {
    value = aws_instance.myapp-server.public_ip
}

resource "aws_key_pair" "ssh-key" {
    key_name = "sever-key-2"
    public_key = "${file(var.public_key_location)}"
}

resource "aws_instance" "myapp-server" {
    ami = data.aws_ami.lattest-amazon-linux-image.id
    instance_type = var.instance_type

    subnet_id = aws_subnet.myapp-subnet-1.id
    vpc_security_group_ids = [aws_default_security_group.default-sg.id]
    availability_zone = var.avail_zone

    /* This is one alternative to use key-pair, the other, you have to creat a resource
    associate_public_ip_address = true
    key_name = "sever-keypair"*/

    associate_public_ip_address = true
    key_name = aws_key_pair.ssh-key.key_name

    /*This gives you an oppotunity to run some sommand on your sever immidiately after creation. 
    Unfortunately terraform is not designed to managed application*/
    
    #user_data= file("entry-script.sh")
    /*instaed of using the data dirrectly, we could use "provision" which is define below. but then we must 
    use "connection" which defines how we connect to the sever " */


    connection {
        type = "ssh"
        host = self.public_ip # it could also be sometherserver.public_ip
        user = "ec2-user"
        private_key = file(var.private_key_location)
    }

    provisioner "file" {
        source = "entry-script.sh"
        destination = "home/ec2-user/entry-script-on-ec2.sh" 
    }# this provisioner is principaly use to copy file from local system to remote server in this care our ec2-instance

    provisioner "remote-exec" {
        script = file("entry-script.sh") # for this to execute, te .sh file has to be copied to the remote server. that is what the preceeding provisioner does
    }

    provisioner "local-exec" {
        command = "echo ${self.public_ip} > output.txt"
    } # it is adviseable to use local provider instead of local exec because local provide has a way of comparing if something changed as it
    #the desired and actual state ie declarative model is maintained

    tags = {
        Name: "${var.env_prefix}-sever"
    }

}### in case there is an error in say the script file, it wont stop the server from being created but it will out put an error with a message telling
#you what error it is