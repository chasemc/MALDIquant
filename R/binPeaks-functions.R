## binPeaks
##  binning peaks by splitting at the largest gap
##  This is a wrapper function around .binPeaks which prepares the peak list
##  before and recreates a correct peak list after binning.
##
## params:
##  l: list of MassPeaks objects
##  method: character, grouper to used (strict: don't allow multiple peaks of
##          the same sample in the same bin, relaxed: allow them)
##  tolerance: double, maximal deviation of a peak position to be
##             considered as same peak
##
## returns:
##  a list of adjusted MassPeaks objects
##
binPeaks <- function(l, method=c("strict", "relaxed"), tolerance=0.002) {

  ## test arguments
  .stopIfNotIsMassPeaksList(l)

  method <- match.arg(method)

  ## fetch all masses from all input peak lists
  mass <- unname(.unlist(lapply(l, function(x)x@mass)))

  ## fetch all intensities from all input peak lists
  intensities <- .unlist(lapply(l, function(x)x@intensity))

  ## fetch all snr
  snr <- .unlist(lapply(l, function(x)x@snr))

  ## store original mass sample number/id
  samples <- rep.int(seq_along(l), lengths(l))

  ## sort values by mass
  s <- sort.int(mass, index.return=TRUE)
 
  ## reorder mass by sorted mass index
  mass <- s$x
  
  ## reorder intensities by sorted mass index
  intensities <- intensities[s$ix]
                      
  ## reorder snr with sorted mass index
  snr <- snr[s$ix]
  samples <- samples[s$ix]

  ## select grouper
  grouper <- switch(method,
            "strict"  = {
              .grouperStrict
            },
            "relaxed" = {
              .grouperRelaxed
            }
  )

  ## binning
  mass <- .binPeaks(mass=mass, intensities=intensities, samples=samples,
                    tolerance=tolerance, grouper=grouper)

  ## re-sort mass (order could change if "relaxed" is used)
  if (method == "relaxed") {
    s <- sort.int(mass, index.return=TRUE)
    mass <- s$x
    intensities <- intensities[s$ix]
    snr <- snr[s$ix]
    samples <- samples[s$ix]
  }

  ## group mass/intensities/snr by sample ids
  lIdx <- split(seq_along(mass), samples)

  ## create adjusted peak list
  l <- .mapply(FUN=function(p, i) {
    p@mass <- mass[i]
    p@intensity <- intensities[i]
    p@snr <- snr[i]
    p
  }, p=l, i=lIdx)

  l
}

## .binPeaks
##  binning peaks by splitting at the largest gap
##
## params:
##  mass: double, sorted mass
##  intensities: double, corresponding intensities
##  samples: double, corresponding sample id numbers
##  tolerance: double, maximal deviation of a peak position to be
##             considered as same peak
##  grouper: grouping function
##  ...: arguments passed to grouping function
##
## returns:
##  vector (double) of modified mass
##
.binPeaks <- function(mass, intensities, samples, tolerance,
            grouper=.grouperStrict, ...) {
  n <- length(mass)

  ## calculate difference
  d <- diff(mass)

  ## grouper function
  grouper <- match.fun(grouper)

  ## stack based implementation taken from
  ## caMassClass 1.9 R/msc.peaks.clust.R written by
  ## Jarek Tuszynski <jaroslaw.w.tuszynski@saic.com>
  ## it is a lot of faster than recursion

  ## store boundaries in a stack
  nBoundaries <- max(20L, floor(3L * log(n)))
  boundary <- list(left=double(nBoundaries), right=double(nBoundaries))

  currentBoundary <- 1L
  boundary$left[currentBoundary] <- 1L
  boundary$right[currentBoundary] <- n

  ## workhorse loop
  while (currentBoundary > 0L) {
    ## find largest gap
    left <- boundary$left[currentBoundary]
    right <- boundary$right[currentBoundary]
    currentBoundary <- currentBoundary - 1L
    gaps <- d[left:(right - 1L)]

    gapIdx <- which.max(gaps) + left - 1L

    ## left side
    l <- grouper(mass=mass[left:gapIdx],
                 intensities=intensities[left:gapIdx],
                 samples=samples[left:gapIdx],
                 tolerance=tolerance, ...)
    ## further splitting needed?
    if (is.na(l[1L])) {
      currentBoundary <- currentBoundary + 1L
      boundary$left[currentBoundary] <- left
      boundary$right[currentBoundary] <- gapIdx
    } else {
      mass[left:gapIdx] <- l
    }

    ## right side
    r <- grouper(mass=mass[(gapIdx + 1L):right],
                 intensities=intensities[(gapIdx + 1L):right],
                 samples=samples[(gapIdx + 1L):right],
                 tolerance=tolerance, ...)
    ## further splitting needed?
    if (is.na(r[1L])) {
      currentBoundary <- currentBoundary + 1L
      boundary$left[currentBoundary] <- gapIdx + 1L
      boundary$right[currentBoundary] <- right
    } else {
      mass[(gapIdx + 1L):right] <- r
    }

    ## stack size have to be increased?
    ## (should rarely happen because recursion deep is mostly < 20)
    if (currentBoundary == nBoundaries) {
      nBoundaries <- floor(nBoundaries * 1.5)
      boundary$left <- c(boundary$left,
                         double(nBoundaries - currentBoundary))
      boundary$right <- c(boundary$right,
                          double(nBoundaries - currentBoundary))
    }
  }
  mass
}
