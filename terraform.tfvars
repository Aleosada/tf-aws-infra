key_name = "awskeypair"
private_key_path = "/home/aleosada/.ssh/awskeypair.pem"

web_network_address_space = {
  development = "10.1.0.0/16"
}
shared_network_address_space = {
  development = "10.2.0.0/16"
}
transit_network_address_space = {
  development = "10.3.0.0/16"
}
nginx_instance_size = {
  development = "t2.micro"
}
nginx_instance_count = {
  development = 1
}
db_instance_size = {
  development = "t2.micro"
}
db_instance_count = {
  development = 1
}
nat_instance_size = {
  development = "t2.micro"
}
nat_instance_count = {
  development = 1
}
web_subnet_count = {
  development = 1
}
shared_priv_subnet_count = {
  development = 1
}
shared_pub_subnet_count = {
  development = 1
}
