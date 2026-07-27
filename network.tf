# ─── VPC ────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

# ─── Internet Gateway ────────────────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# ─── Frontend Subnets (public) ───────────────────────────────────────────────
resource "aws_subnet" "frontend" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.frontend_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-frontend-${count.index + 1}" }
}

# ─── Backend Subnets (private) ───────────────────────────────────────────────
resource "aws_subnet" "backend" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.backend_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags              = { Name = "${var.project_name}-backend-${count.index + 1}" }
}

# ─── Database Subnets (isolated) ─────────────────────────────────────────────
resource "aws_subnet" "db" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags              = { Name = "${var.project_name}-db-${count.index + 1}" }
}

# ─── NAT Gateway ─────────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.frontend[0].id
  tags          = { Name = "${var.project_name}-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

# ─── Route Table: Frontend → IGW ─────────────────────────────────────────────
resource "aws_route_table" "frontend" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-rt-frontend" }
}

resource "aws_route_table_association" "frontend" {
  count          = 3
  subnet_id      = aws_subnet.frontend[count.index].id
  route_table_id = aws_route_table.frontend.id
}

# ─── Route Table: Backend → NAT ──────────────────────────────────────────────
resource "aws_route_table" "backend" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.project_name}-rt-backend" }
}

resource "aws_route_table_association" "backend" {
  count          = 3
  subnet_id      = aws_subnet.backend[count.index].id
  route_table_id = aws_route_table.backend.id
}

# ─── Route Table: DB → Blackhole (nema rute) ─────────────────────────────────
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-rt-db" }
}

resource "aws_route_table_association" "db" {
  count          = 3
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}
