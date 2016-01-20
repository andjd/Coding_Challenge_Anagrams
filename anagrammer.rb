require 'set'
class PhraseSet < Set
  def to_s
    self.to_a.join " "
  end
end

# Alphagrams are representations of words that share the same set of letters.
class Alphagram
  include Comparable
  attr_reader :gram, :words, :subs

  def self.convert word
    word.downcase.delete('^a-z').split("").sort.join
  end


  def initialize word, valid = true
    @gram = Alphagram.convert word
    @words = PhraseSet.new
    add_word word if valid
    @subs = AlphagramCollection.new
  end

  def add_word word
    @words << word 
  end

  def merge other
    out = self.dup
    out.merge! other
  end

  def merge! other
    unless self === other
      raise ArgumentError("merging Alphagrams requires each Alphagram instance share the same character set")
    end
    @words.merge other.words
    @subs.merge! other.subs

    self
  end

  def to_s
    gram.dup
  end

  def === other
    unless other.is_a? Alphagram
      other = Alphagram.new other
    end
    gram == other.gram
  end

  def size
    gram.length
  end

  def <=> other
    size <=> other.size
  end

  def - other
    remainder_gram = self.to_s
    self_i = 0
    other_i = 0

    while other_i < other.size 
      case remainder_gram[self_i] <=> other.gram[other_i]
      when 0
        remainder_gram[self_i] = ""
        other_i += 1
      when -1
        self_i += 1
      when 1, nil
        return nil # other contains a character not in self and cannot be subtracted from self
      end
    end
    return Alphagram.new(remainder_gram, false)
  end

  def + other
    conjoined_gram = Alphagram.new(self.to_s + other.to_s, false)
    conjoined_gram.subs.push(self).push(other)
    conjoined_gram
  end

  def word_count
    words.length + subs.values.inject(0) {|count, sub| count + sub.word_count}
  end

# recursively finds all sets of words that validly combine to form Alphagram
  def phrases
    out = words.dup
    keys = subs.keys.each.to_a
    subs.keys.each do |key1|
      keys[(keys.index(key1) + 1..-1)].each do |key2|
        next unless self === subs[key1] + subs[key2] 
        subs[key1].phrases.each do |phrase1|
          subs[key2].phrases.each do |phrase2|
            out << phrase1.to_s + " " + phrase2.to_s
          end
        end
      end
    end
    out
  end

  # Allows hash to reflect changes in nested sub-alphagram structure
  def hash
    gram.hash ^ words.hash ^ (subs.values.inject(0) { |hash, gram| hash ^ gram.hash })
  end

end

# An unordered collection of Alphagrams, indexed by their string representation. 
# Collisions are merged
class AlphagramCollection < Hash
  def push gram
    raise ArgumentError.new "Cannot coerce #{gram.class} into an Alphagram." unless gram.is_a? Alphagram
    if self[gram.to_s]
      self[gram.to_s].merge! gram
    else
      self[gram.to_s] = gram
    end
    self
  end

  def merge! other
    raise ArgumentError.new "Cannot coerce #{other.class} into an AlphagramCollection." unless other.is_a? AlphagramCollection
    super(other) { |key, gram1, gram2| gram1.merge gram2 }
  end

  def merge other
    out = self.dup
    out.merge! other
  end

  # Allows hash value to reflect nested changes
  def hash
    super ^ (self.values.inject { |hash, gram| hash ^ gram.hash })
  end

end

class AnagramFinder

  # Does not presume that an anagram will be the same number of words as the input phrase.
  # Optimizes typical but not worst-case runtime by prioritizing validation of candidate phrases with longer and fewer words.
  attr_accessor :target_alphagram, :sub_grams, :md5, :candidates, :checked_candidates

  def initialize(phrase, hash, word_file = "wordlist.txt")
    @file = word_file
    @phrase = phrase
    @target_alphagram = Alphagram.new phrase
    @md5 = hash
    @sub_grams = AlphagramCollection.new
    @candidates = Array.new
    @checked_candidates = Set.new
  end

  def self.find(*args)
    finder = AnagramFinder.new(*args)
    finder.parse_and_validate
  end

  def parse_and_validate
    # parses wordlist file and gropus words by length
    buckets = bucketize_words

    # parses longer words first to optimize typical case as the vast majority of possible candidates contain many small words.
    buckets.keys.sort.reverse.each do |key|
      buckets[key].each do |word|
        parse_word word
      end
      result = find
      return result if result
    end
    nil # no valid candidates found
  end

  private

  def parse_word word
    new_gram = Alphagram.new word
    
    # If word matches alphagram in sub_grams, simply add word to existing alphagram
    existing = sub_grams[new_gram.to_s]
    if existing
      existing.add_word word
      return nil
    end

    # calculate the complementary alphagram for word
    remainder = target_alphagram - new_gram
    return nil if remainder.nil? # word cannot be part of the anagram phrase

    # find if complementary alphagram exists in sub_grams
    remainder_existing = sub_grams[remainder.to_s]
    if remainder_existing
      candidates << new_gram + remainder_existing
      return nil
    end

   #add new_gram to all sub_grams and adds valid combinations to sub_grams 
    combine new_gram, remainder  

    sub_grams.push new_gram

    nil
  end

   # 
  def find
    candidates.each do |candidate|
      # Skips candidates that have already been checked
      next if checked_candidates.include? candidate.hash
      checked_candidates << candidate.hash

      candidate.phrases.each do |phrase|

        # Caluclates all permutations of phrase and checks them against the md5 hash
        validated_phrase = validate phrase
        return validated_phrase if validated_phrase
      end
    end
    nil #no valid candidates found
  end


  def bucketize_words
    f = File.open @file
    word_buckets = Hash.new

    while word = f.gets
      word.chomp!
      # cleaning input a little
      next unless word.index /[aeiouy]/
      word.slice!(-2, 2) if word[-2] == "\'"

      word_buckets[word.length] ||= Array.new
      word_buckets[word.length].push word

    end

    f.close
    word_buckets
  end

  def validate phrase
    require 'digest'
    phrase.split.permutation do |candidate|
      candidate = candidate.join " "
      return candidate if md5 == Digest::MD5.hexdigest(candidate)
    end
    nil
  end

  def combine gram, remainder
    new_subs = AlphagramCollection.new
    sub_grams.each_value do |sub|

      next if (remainder - sub).nil?

      new_subs.push sub + gram
    end

    sub_grams.merge! new_subs
  end

end



if $PROGRAM_NAME == __FILE__
puts AnagramFinder.find("poultry outwits ants", "4624d200580677270a54ccff86b9610e")
end






