package HMF::Pipeline::Amber;

use FindBin::libs;
use discipline;

use File::Basename;
use File::Spec::Functions;

use HMF::Pipeline::Config qw(createDirs addSubDir sampleBamAndJobs sampleControlBamsAndJobs);
use HMF::Pipeline::Job qw(fromTemplate checkReportedDoneFile markDone);
use HMF::Pipeline::Metadata;
use HMF::Pipeline::Sge qw(qsubTemplate);
use HMF::Pipeline::Template qw(writeFromTemplate);

use parent qw(Exporter);
our @EXPORT_OK = qw(run);


sub run {
    my ($opt) = @_;

    say "\n### SCHEDULING AMBER ###";
    $opt->{RUNNING_JOBS}->{'amber'} = [];

    my $dirs = createDirs($opt->{OUTPUT_DIR}, amber => "amber");
    my ($ref_sample, $tumor_sample, $ref_bam_path, $tumor_bam_path, $joint_name, $running_jobs) = sampleControlBamsAndJobs($opt);
    my $done_file = checkReportedDoneFile("Amber_$joint_name", undef, $dirs, $opt) or return;

    my @amber_jobs;
    push @amber_jobs, runAmberPileup($ref_sample, $ref_bam_path, $running_jobs, $dirs, $opt);
    push @amber_jobs, runAmberPileup($tumor_sample, $tumor_bam_path, $running_jobs, $dirs, $opt);
    push @amber_jobs, runAmber($tumor_sample, $ref_bam_path, $tumor_bam_path, \@amber_jobs, $dirs, $opt);
    push @amber_jobs, markDone($done_file, \@amber_jobs, $dirs, $opt);
    push @{$opt->{RUNNING_JOBS}->{'amber'}}, @amber_jobs;
    return;
}

sub runAmber {
    my ($tumor_sample, $ref_bam_path, $tumor_bam_path, $running_jobs, $dirs, $opt) = @_;

    say "\n### SCHEDULING AMBER ###";
    my $job_id = fromTemplate(
        "Amber",
        undef,
        1,
        qsubTemplate($opt, "AMBER"),
        $running_jobs,
        $dirs,
        $opt,
        tumor_sample => $tumor_sample,
        ref_bam_path => $ref_bam_path,
        tumor_bam_path => $tumor_bam_path,
    );

    return $job_id;
}

sub runAmberPileup {
    my ($sample, $sample_bam, $running_jobs, $dirs, $opt) = @_;

    say "\n### SCHEDULING AMBER PILEUP ON $sample ###";
    my $job_id = fromTemplate(
        "AmberPileup",
        $sample,
        1,
        qsubTemplate($opt, "AMBER"),
        $running_jobs,
        $dirs,
        $opt,
        sample => $sample,
        sample_bam => $sample_bam,
    );

    return $job_id;
}

1;