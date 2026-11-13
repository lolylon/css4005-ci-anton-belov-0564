output "vpc_id" { value = aws_vpc.this.id }
output "vpc_cidr" { value = aws_vpc.this.cidr_block }
output "public_subnet_ids" { value = [aws_subnet.public_a.id, aws_subnet.public_b.id] }
output "app_subnet_ids" { value = [aws_subnet.app_a.id, aws_subnet.app_b.id] }
output "db_subnet_ids" { value = [aws_subnet.db_a.id, aws_subnet.db_b.id] }
output "subnet_cidrs" {
  value = {
    public_a = aws_subnet.public_a.cidr_block
    public_b = aws_subnet.public_b.cidr_block
    app_a    = aws_subnet.app_a.cidr_block
    app_b    = aws_subnet.app_b.cidr_block
    db_a     = aws_subnet.db_a.cidr_block
    db_b     = aws_subnet.db_b.cidr_block
  }
}
output "sg_alb_id" { value = aws_security_group.alb.id }
output "sg_k3s_id" { value = aws_security_group.k3s.id }
output "sg_db_id" { value = aws_security_group.db.id }
output "nat_instance_id" { value = aws_instance.nat.id }
output "nat_public_ip" { value = aws_eip.nat.public_ip }
