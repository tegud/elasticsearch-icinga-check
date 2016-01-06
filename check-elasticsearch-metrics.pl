#!/usr/bin/perl
use LWP::UserAgent; 
use JSON::XS;
use Getopt::Std;
use Time::HiRes qw(gettimeofday);
use Time::Piece;

my $args = "rc:w:s:a:t:f:q:h:p:";
getopts("$args", \%opt);

if(!defined $opt{s}){
  return inputError('s');
}
if(!defined $opt{c} ){
  return inputError('c');
}
if(!defined $opt{w}){
  return inputError('w');
}
if(!defined $opt{a}){
  return inputError('a');
}
if(!defined $opt{t}){
  return inputError('t');
}  
if(!defined $opt{f} ){
  return inputError('f');
}
if(!defined $opt{q}){
  return inputError('q');
}
if(!defined $opt{h}){
  return inputError('h');
}
if(!defined $opt{p}){
  $opt{p} = 9200;
}

my $rawNow = localtime;
my $rawFrom = $rawNow - $opt{s};
my $now = $rawNow->epoch * 1000;
my $fromTime = $rawFrom->epoch * 1000;
my $critical = $opt{c};
my $warning = $opt{w};
my $reverse = $opt{r};
my $aggregationName = $opt{a};
my $aggregationType = $opt{t};
my $field = $opt{f};
my $query = $opt{q};
my $host = $opt{h};
my $port = $opt{p};

makeElasticsearchRequest();

sub makeElasticsearchRequest {
  my $ua = LWP::UserAgent->new;
  $ua->agent("Icinga Check/0.1 ");

  my $indices = "metrics-".$rawNow->year.".".$rawNow->strftime("%m").",metrics-".$rawNow->add_months(-1)->year.".".$rawNow->add_months(-1)->strftime("%m");

  my $req = HTTP::Request->new(POST => "http://$host:$port/$indices/_search");
  $req->content_type('application/json');
  my $content = "{
    \"size\": 0,
    \"query\": {
      \"filtered\": {
        \"query\": {
          \"query_string\": {
            \"query\": \"$query\",
            \"analyze_wildcard\": true
          }
        },
        \"filter\": {
          \"bool\": {
            \"must\": [
              {
                \"range\": {
                  \"\@timestamp\": {
                    \"gte\": $fromTime,
                    \"lte\": $now,
                    \"format\": \"epoch_millis\"
                  }
                }
              }
            ],
            \"must_not\": []
          }
        }
      }
    },
    \"aggs\": {
      \"$aggregationName\": {
        \"$aggregationType\": {
          \"field\": \"$field\"
        }
      }
    }
  }";
  $req->content($content);
  my $res = $ua->request($req);
  parseElasticsearchResponse($res);
}



sub parseElasticsearchResponse {
  my ($res) = @_;
  if ($res->is_success) {
    my $content = $res->content;
    my %parsed = %{decode_json $content};
    my %aggregations = %{$parsed{aggregations}};
    my %aggValue = %{$aggregations{$aggregationName}};
    my $value = $aggValue{value};
    my $alertStatus = getAlertStatus($value);
    print "\nCurrent Value: $value, Critical: $critical, Warning: $warning\n";
    exit $alertStatus;
  }
  else {
      print $res->status_line, " from elasticsearch\n";
      exit 4;
  }
}

sub getAlertStatus {
  my ($esvalue) = @_;
  if($reverse){
    if($esvalue <= $critical){
      return 2;
    }
    if($esvalue <= $warning){
      return 3;
    }
  }
  else {
    if($esvalue >= $critical){
      return 2;
    }
    if($esvalue >= $warning){
      return 3;
    }
  }
}

sub help {
  print "\nObtains metrics from elasticsearch to power Icinga alerts\n";
  print "\nUsage: check-elasticsearch-metrics.pl [OPTIONS]\n";
  print "\nRequired Settings:\n";
  print "\t-c [threshold]: critical threshold\n";
  print "\t-w [threshold]: warning threshold\n";
  print "\t-s [seconds]: number of seconds from now to check\n";
  print "\t-a [name]: aggregation name\n";
  print "\t-t [type]: aggregation type\n";
  print "\t-f [field_name]: the name of the field to aggregate\n";
  print "\t-q [query_string]: the query to run in elasticsearch\n";
  print "\t-h [host]: elasticsearch host\n\n";
  print "\tOptional Settings:\n";
  print "\t-?: this help message\n";
  print "\t-r: reverse threshold (so amounts below threshold values will alert)\n";
  print "\t-q [port]: elasticsearch port (defaults to 9200)\n\n";
  print "Error codes:\n";
  print "\t0: Everything OK, check passed\n";
  print "\t1: Warning threshold breached\n";
  print "\t2: Critical threshold breached\n";
  print "\t4: Unknown, encountered an error querying elasticsearch\n";
}

sub inputError {
  my ($option) = @_;
  print STDERR "\n\n\t\tMissing required parameter \"$option\"\n\n";
  help();
  exit 4;
}